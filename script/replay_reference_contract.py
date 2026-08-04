"""Shared contracts for RowPlay replay-reference tooling."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


DOMAIN_TO_EQUIPMENT_SPORT = {
    "rower": "row",
    "skierg": "ski",
    "bike": "bike",
}
DOMAIN_SPORTS = tuple(DOMAIN_TO_EQUIPMENT_SPORT)
EQUIPMENT_SPORTS = tuple(DOMAIN_TO_EQUIPMENT_SPORT.values())


def validate_motion_manifest(
    manifest: Any,
    athlete_contract: Any,
) -> list[str]:
    """Return motion-order and athlete-contract metadata mismatches."""
    if not isinstance(manifest, dict):
        return ["motion manifest root must be an object"]
    if not isinstance(athlete_contract, dict):
        return ["athlete contract root must be an object"]

    errors: list[str] = []
    sports = manifest.get("sports")
    if sports != list(DOMAIN_SPORTS):
        errors.append(
            "motion manifest sports must equal the supported domain order exactly"
        )

    animation = athlete_contract.get("animation")
    contract_clips = animation.get("clips") if isinstance(animation, dict) else None
    motion_clips = manifest.get("clips")
    if not isinstance(contract_clips, list):
        return errors + ["athlete contract animation.clips must be an array"]
    if not isinstance(motion_clips, list):
        return errors + ["motion manifest clips must be an array"]
    if len(contract_clips) != len(DOMAIN_SPORTS):
        errors.append("athlete contract must contain one clip for each supported sport")
    if len(motion_clips) != len(DOMAIN_SPORTS):
        errors.append("motion manifest must contain one clip for each supported sport")

    comparable_count = min(
        len(DOMAIN_SPORTS), len(contract_clips), len(motion_clips)
    )
    for index in range(comparable_count):
        sport = DOMAIN_SPORTS[index]
        contract_clip = contract_clips[index]
        motion_clip = motion_clips[index]
        if not isinstance(contract_clip, dict):
            errors.append(f"athlete contract {sport} clip must be an object")
            continue
        if not isinstance(motion_clip, dict):
            errors.append(f"motion manifest {sport} clip must be an object")
            continue

        expected = {
            "sport": sport,
            "clipName": contract_clip.get("name"),
            "durationSeconds": contract_clip.get("durationSeconds"),
            "driveEnd": contract_clip.get("driveEnd"),
            "phaseLandmarks": contract_clip.get("phaseLandmarks"),
        }
        for field, expected_value in expected.items():
            if motion_clip.get(field) != expected_value:
                errors.append(
                    f"motion manifest {sport} {field} drifted from athlete contract"
                )
    return errors


def validate_equipment_manifest(
    manifest: Any,
    equipment_root: Path,
    *,
    expected_commit: str,
    expected_source_glb_sha256: str,
) -> list[str]:
    """Return every committed-equipment contract mismatch."""
    errors: list[str] = []
    if not isinstance(manifest, dict):
        return ["equipment manifest root must be an object"]

    if manifest.get("sourceCommit") != expected_commit:
        errors.append("equipment manifest pinned to a different commit")
    if manifest.get("sourceGlbSha256") != expected_source_glb_sha256:
        errors.append("equipment manifest source GLB hash drifted")

    packages = manifest.get("packages")
    if not isinstance(packages, list):
        return errors + ["equipment manifest packages must be an array"]

    seen_sports: set[str] = set()
    for index, entry in enumerate(packages):
        if not isinstance(entry, dict):
            errors.append(f"equipment package {index} must be an object")
            continue

        sport = entry.get("sport")
        label = sport if isinstance(sport, str) and sport else f"package {index}"
        if sport not in EQUIPMENT_SPORTS:
            errors.append(f"equipment {label} has unsupported sport {sport!r}")
        elif sport in seen_sports:
            errors.append(f"equipment manifest duplicates sport {sport}")
        else:
            seen_sports.add(sport)

        package_path = _artifact_path(
            equipment_root, entry.get("file"), f"equipment {label} package", errors
        )
        if package_path is not None:
            if not package_path.is_file():
                errors.append(f"missing equipment package {package_path.name}")
            else:
                package_hash = _sha256(package_path)
                if package_hash != entry.get("sha256"):
                    errors.append(f"equipment package hash mismatch: {package_path.name}")
                byte_count = entry.get("byteCount")
                if not isinstance(byte_count, int) or isinstance(byte_count, bool):
                    errors.append(f"equipment package byte count missing: {package_path.name}")
                elif package_path.stat().st_size != byte_count:
                    errors.append(f"equipment package byte count mismatch: {package_path.name}")

        contract_path = _artifact_path(
            equipment_root,
            entry.get("contractFile"),
            f"equipment {label} contract",
            errors,
        )
        if contract_path is None:
            continue
        if not contract_path.is_file():
            errors.append(f"missing equipment contract {contract_path.name}")
            continue
        if _sha256(contract_path) != entry.get("contractSha256"):
            errors.append(f"equipment contract hash mismatch: {contract_path.name}")
        try:
            sidecar = json.loads(contract_path.read_text())
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            errors.append(f"invalid equipment contract {contract_path.name}: {error}")
            continue
        if not isinstance(sidecar, dict):
            errors.append(f"equipment contract root must be an object: {contract_path.name}")
            continue
        if sidecar.get("sourceCommit") != expected_commit:
            errors.append(f"equipment contract pinned to a different commit: {contract_path.name}")
        if sidecar.get("sourceGlbSha256") != expected_source_glb_sha256:
            errors.append(f"equipment contract source GLB hash drifted: {contract_path.name}")
        if sidecar.get("sport") != sport:
            errors.append(f"equipment contract sport does not match manifest: {contract_path.name}")

    if len(packages) != len(EQUIPMENT_SPORTS) or seen_sports != set(EQUIPMENT_SPORTS):
        errors.append("equipment manifest must contain one package for each supported sport")
    return errors


def _artifact_path(
    root: Path,
    value: Any,
    label: str,
    errors: list[str],
) -> Path | None:
    if not isinstance(value, str) or not value:
        errors.append(f"{label} file name missing")
        return None
    path = root / value
    if path.parent.resolve() != root.resolve():
        errors.append(f"{label} must be directly under the equipment directory")
        return None
    return path


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()
