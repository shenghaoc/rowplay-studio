#!/usr/bin/env python3
"""Validate the committed RowPlay reference bundle's internal consistency.

Unlike ``sync_rowplay_reference.py --check`` (which needs the sibling RowPlay
checkout), this gate validates only the committed bundle: manifest hashes
match the committed files, every artifact the manifests promise exists, and
all manifests agree on one pinned commit.  CI-safe.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
REFERENCE_ROOT = REPO_ROOT / "Sources" / "RowPlayStudio" / "Resources" / "ReplayReference"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fail(message: str) -> "sys.NoReturn":
    print(f"VALIDATE FAILED: {message}", file=sys.stderr)
    raise SystemExit(1)


def load(path: Path) -> dict:
    if not path.exists():
        fail(f"missing {path.relative_to(REPO_ROOT)}")
    return json.loads(path.read_text())


def main() -> None:
    source = load(REFERENCE_ROOT / "rowplay-source.json")
    pinned = source.get("pinnedRowPlayMainCommit", "")
    if len(pinned) != 40:
        fail("rowplay-source.json pinned commit malformed")

    athlete = load(REFERENCE_ROOT / "athlete" / "rowplay-athlete-source.json")
    if athlete.get("pinnedCommit") != pinned:
        fail("athlete manifest pinned to a different commit")

    contract_path = REFERENCE_ROOT / "athlete" / "rowplay-athlete-v4.contract.json"
    usdz_path = REFERENCE_ROOT / "athlete" / "rowplay-athlete-v4.usdz"
    if sha256(contract_path) != athlete.get("contractSha256"):
        fail("contract hash mismatch")
    if sha256(usdz_path) != athlete.get("usdzSha256"):
        fail("athlete USDZ hash mismatch")
    contract = json.loads(contract_path.read_text())
    bones = contract.get("bones", {})
    if bones.get("semanticCount") != athlete.get("semanticBoneCount"):
        fail("semantic bone count drifted")
    if bones.get("helperCount") != athlete.get("helperCount"):
        fail("helper count drifted")

    motion = load(REFERENCE_ROOT / "motion" / "rowplay-motion-manifest.json")
    if motion.get("sourceCommit") != pinned:
        fail("motion manifest pinned to a different commit")
    motion_bin = REFERENCE_ROOT / "motion" / "rowplay-motion.bin"
    if not motion_bin.exists():
        fail("missing rowplay-motion.bin")
    if sha256(motion_bin) != motion.get("motionBinSha256"):
        fail("motion.bin hash mismatch")
    if motion_bin.stat().st_size != motion.get("motionBinByteCount"):
        fail("motion.bin size mismatch")
    expected_floats = (
        len(motion.get("sports", []))
        * motion.get("samplesPerSport", 0)
        * len(motion.get("boneNames", []))
        * motion.get("floatsPerBone", 0)
    )
    if motion_bin.stat().st_size != expected_floats * 4:
        fail("motion.bin layout does not match its manifest")

    equipment = load(REFERENCE_ROOT / "equipment" / "rowplay-equipment-manifest.json")
    if equipment.get("sourceCommit") != pinned:
        fail("equipment manifest pinned to a different commit")
    for entry in equipment.get("packages", []):
        package = REFERENCE_ROOT / "equipment" / entry["file"]
        if not package.exists():
            fail(f"missing equipment package {entry['file']}")
        if sha256(package) != entry.get("sha256"):
            fail(f"equipment package hash mismatch: {entry['file']}")
        sidecar = REFERENCE_ROOT / "equipment" / entry["contractFile"]
        if not sidecar.exists():
            fail(f"missing equipment contract {entry['contractFile']}")
        if sha256(sidecar) != entry.get("contractSha256"):
            fail(f"equipment contract hash mismatch: {entry['contractFile']}")
        sidecar_json = json.loads(sidecar.read_text())
        if sidecar_json.get("sourceCommit") != pinned:
            fail(f"{entry['contractFile']} pinned to a different commit")

    environment = load(REFERENCE_ROOT / "environment" / "environment-manifest.json")
    if environment.get("sourceCommit") != pinned:
        fail("environment manifest pinned to a different commit")
    for texture in environment.get("textures", []):
        path = REFERENCE_ROOT / "environment" / texture["file"]
        if not path.exists():
            fail(f"missing texture {texture['file']}")
        if sha256(path) != texture.get("sha256"):
            fail(f"texture hash mismatch: {texture['file']}")

    print(f"reference bundle internally consistent, pinned to {pinned}")


if __name__ == "__main__":
    main()
