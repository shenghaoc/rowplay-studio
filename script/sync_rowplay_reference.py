#!/usr/bin/env python3
"""Sync the RowPlay current-main replay reference bundle into RowPlay Studio.

Reads every artifact from an exact RowPlay Git tree (``git show <commit>:...``)
rather than the working directory, so a developer's local branch or
uncommitted files can never alter the shipped reference.

Usage:
    python3 script/sync_rowplay_reference.py \
        --rowplay-repo /path/to/rowplay \
        --expected-commit <rowplay-main-sha>

    python3 script/sync_rowplay_reference.py ... --check

The bundle written under ``Sources/RowPlayStudio/Resources/ReplayReference/``:

    rowplay-source.json                  top-level pinned source manifest
    athlete/rowplay-athlete-v4.usdz      native derivative of the production athlete
    athlete/rowplay-athlete-v4.contract.json
    athlete/rowplay-athlete-source.json  athlete provenance manifest
    motion/rowplay-motion.bin            sampled semantic-bone clip table
    motion/rowplay-motion-manifest.json
    environment/environment-manifest.json
    environment/textures/<family>/...    CC0 material maps used by the port

Equipment USDZ conversion is Blender-bound and owned by
``script/convert_rowplay_equipment.py``; parity fixtures are owned by
``script/export_rowplay_native_parity.mjs``.  ``--check`` requires the converted
equipment set and validates any layer-owned parity fixtures that are present at
their real test-resource paths.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import subprocess
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
REFERENCE_ROOT = REPO_ROOT / "Sources" / "RowPlayStudio" / "Resources" / "ReplayReference"

SEMANTIC_BONES = [
    "v4Hips", "v4Spine", "v4Chest", "v4Neck", "v4Head",
    "v4LeftClavicle", "v4LeftUpperArm", "v4LeftForearm", "v4LeftHand",
    "v4RightClavicle", "v4RightUpperArm", "v4RightForearm", "v4RightHand",
    "v4LeftUpperLeg", "v4LeftLowerLeg", "v4LeftFoot",
    "v4RightUpperLeg", "v4RightLowerLeg", "v4RightFoot",
]

CLIPS = [
    ("rower", "rowplay-v4-row-cycle"),
    ("skierg", "rowplay-v4-ski-cycle"),
    ("bike", "rowplay-v4-bike-cycle"),
]

DRIVE_END = {"rower": 0.38, "skierg": 0.34, "bike": 0.5}

PHASE_LANDMARKS = {
    "rower": {
        "catch": 0.0, "legDrive": 0.08, "bodyOpen": 0.3, "finish": 0.38,
        "handsAway": 0.54, "bodyOver": 0.72, "slide": 0.88, "loop": 1.0,
    },
    "skierg": {
        "reach": 0.0, "plant": 0.12, "loadedPull": 0.24, "driveEnd": 0.34,
        "release": 0.58, "recover": 0.78, "loop": 1.0,
    },
    "bike": {
        "leftTop": 0.0, "leftPower": 0.25, "opposed": 0.5, "rightPower": 0.75,
        "loop": 1.0,
    },
}

SAMPLES_PER_SPORT = 257
MOTION_FORMAT_VERSION = 2

# CC0 material families consumed by the native environment port
# (diffuse/normal-gl/roughness triplets at 512 px).
ENVIRONMENT_TEXTURE_FAMILIES = [
    "aerial-grass-rock",
    "bark-brown-01",
    "brown-planks-03",
    "brushed-concrete-2",
    "cobblestone-floor-03",
    "concrete-floor-painted",
    "dry-river-pebbles",
    "forest-leaves-04",
    "forrest-ground-01",
    "leafy-grass",
    "rock-01",
    "snow-02",
    "wood-floor",
]

TEXTURE_SUFFIXES = ["diffuse-512.jpg", "normal-gl-512.jpg", "roughness-512.jpg"]


def fail(message: str) -> "sys.NoReturn":
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def git_text(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def git_blob(repo: Path, commit: str, path: str) -> bytes:
    result = subprocess.run(
        ["git", "-C", str(repo), "cat-file", "blob", f"{commit}:{path}"],
        check=True,
        capture_output=True,
    )
    return result.stdout


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# ---------------------------------------------------------------------------
# GLB clip sampling (pure-Python glTF binary parse — no dependencies)
# ---------------------------------------------------------------------------

def parse_glb(data: bytes) -> tuple[dict[str, Any], bytes]:
    magic, version, _length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        fail("athlete GLB magic mismatch")
    if version != 2:
        fail(f"unsupported GLB version {version}")
    offset = 12
    json_chunk: bytes | None = None
    bin_chunk: bytes | None = None
    while offset < len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        payload = data[offset + 8 : offset + 8 + chunk_length]
        if chunk_type == 0x4E4F534A:
            json_chunk = payload
        elif chunk_type == 0x004E4942:
            bin_chunk = payload
        offset += 8 + chunk_length + (-chunk_length) % 4
    if json_chunk is None or bin_chunk is None:
        fail("athlete GLB missing JSON or BIN chunk")
    return json.loads(json_chunk), bin_chunk


def read_accessor(gltf: dict[str, Any], binary: bytes, index: int) -> list[tuple[float, ...]]:
    accessor = gltf["accessors"][index]
    if accessor.get("componentType") != 5126:
        fail(f"accessor {index} is not float32")
    view = gltf["bufferViews"][accessor["bufferView"]]
    components = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[accessor["type"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride") or components * 4
    values: list[tuple[float, ...]] = []
    for element in range(accessor["count"]):
        base = start + element * stride
        values.append(struct.unpack_from(f"<{components}f", binary, base))
    return values


def slerp(a: tuple[float, ...], b: tuple[float, ...], t: float) -> tuple[float, float, float, float]:
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    dot = ax * bx + ay * by + az * bz + aw * bw
    if dot < 0:
        bx, by, bz, bw = -bx, -by, -bz, -bw
        dot = -dot
    if dot > 0.9995:
        x = ax + (bx - ax) * t
        y = ay + (by - ay) * t
        z = az + (bz - az) * t
        w = aw + (bw - aw) * t
    else:
        theta = math.acos(max(-1.0, min(1.0, dot)))
        sin_theta = math.sin(theta)
        wa = math.sin((1 - t) * theta) / sin_theta
        wb = math.sin(t * theta) / sin_theta
        x = ax * wa + bx * wb
        y = ay * wa + by * wb
        z = az * wa + bz * wb
        w = aw * wa + bw * wb
    norm = math.sqrt(x * x + y * y + z * z + w * w) or 1.0
    return (x / norm, y / norm, z / norm, w / norm)


def lerp_vec(a: tuple[float, ...], b: tuple[float, ...], t: float) -> tuple[float, ...]:
    return tuple(av + (bv - av) * t for av, bv in zip(a, b))


class SampledChannel:
    def __init__(self, times: list[float], values: list[tuple[float, ...]], rotation: bool):
        if not times:
            fail("animation channel with no keyframes")
        self.times = times
        self.values = values
        self.rotation = rotation

    def sample(self, time: float) -> tuple[float, ...]:
        times = self.times
        if time <= times[0]:
            return self.values[0]
        if time >= times[-1]:
            return self.values[-1]
        low, high = 0, len(times) - 1
        while high - low > 1:
            middle = (low + high) // 2
            if times[middle] <= time:
                low = middle
            else:
                high = middle
        span = times[high] - times[low]
        t = 0.0 if span <= 0 else (time - times[low]) / span
        if self.rotation:
            return slerp(self.values[low], self.values[high], t)
        return lerp_vec(self.values[low], self.values[high], t)


def sample_motion_table(glb: bytes) -> tuple[bytes, dict[str, Any]]:
    gltf, binary = parse_glb(glb)
    node_names = {index: node.get("name", "") for index, node in enumerate(gltf.get("nodes", []))}
    node_rest: dict[int, dict[str, tuple[float, ...]]] = {}
    for index, node in enumerate(gltf.get("nodes", [])):
        node_rest[index] = {
            "translation": tuple(node.get("translation", (0.0, 0.0, 0.0))),
            "rotation": tuple(node.get("rotation", (0.0, 0.0, 0.0, 1.0))),
            "scale": tuple(node.get("scale", (1.0, 1.0, 1.0))),
        }
    animations = {
        animation.get("name", ""): animation for animation in gltf.get("animations", [])
    }

    payload = bytearray()
    clip_manifests: list[dict[str, Any]] = []
    for sport, clip_name in CLIPS:
        animation = animations.get(clip_name)
        if animation is None:
            fail(f"clip {clip_name!r} missing from athlete GLB")
        channels: dict[tuple[str, str], SampledChannel] = {}
        duration = 0.0
        for channel in animation["channels"]:
            target = channel["target"]
            bone = node_names.get(target.get("node", -1), "")
            path = target["path"]
            if bone not in SEMANTIC_BONES or path not in ("translation", "rotation", "scale"):
                continue
            sampler = animation["samplers"][channel["sampler"]]
            if sampler.get("interpolation", "LINEAR") not in ("LINEAR", "STEP"):
                fail(f"unsupported interpolation in {clip_name!r}")
            times = [value[0] for value in read_accessor(gltf, binary, sampler["input"])]
            values = read_accessor(gltf, binary, sampler["output"])
            channels[(bone, path)] = SampledChannel(times, values, path == "rotation")
            duration = max(duration, times[-1])
        if duration <= 0:
            fail(f"clip {clip_name!r} has zero duration")
        rest_by_name = {
            node_names[index]: rest for index, rest in node_rest.items()
            if node_names[index] in SEMANTIC_BONES
        }
        for phase_index in range(SAMPLES_PER_SPORT):
            time = duration * phase_index / SAMPLES_PER_SPORT
            for bone in SEMANTIC_BONES:
                rest = rest_by_name.get(bone) or {
                    "translation": (0.0, 0.0, 0.0),
                    "rotation": (0.0, 0.0, 0.0, 1.0),
                    "scale": (1.0, 1.0, 1.0),
                }
                translation_channel = channels.get((bone, "translation"))
                rotation_channel = channels.get((bone, "rotation"))
                scale_channel = channels.get((bone, "scale"))
                translation = (
                    translation_channel.sample(time)
                    if translation_channel
                    else rest["translation"]
                )
                rotation = (
                    rotation_channel.sample(time) if rotation_channel else rest["rotation"]
                )
                scale = scale_channel.sample(time) if scale_channel else rest["scale"]
                payload += struct.pack(
                    "<10f",
                    *translation,
                    *rotation,
                    *scale,
                )
        clip_manifests.append(
            {
                "sport": sport,
                "clipName": clip_name,
                "durationSeconds": duration,
                "driveEnd": DRIVE_END[sport],
                "phaseLandmarks": PHASE_LANDMARKS[sport],
                "animatedTrackCount": len(channels),
            }
        )

    manifest = {
        "formatVersion": MOTION_FORMAT_VERSION,
        "layout": "float32-little-endian [sport][phase][bone][tx ty tz rx ry rz rw sx sy sz]",
        "samplesPerSport": SAMPLES_PER_SPORT,
        "sports": [sport for sport, _ in CLIPS],
        "boneNames": SEMANTIC_BONES,
        "floatsPerBone": 10,
        "clips": clip_manifests,
        "interpolation": {
            "translation": "linear",
            "scale": "linear",
            "rotation": "shortest-path normalized (slerp source keys)",
        },
    }
    return bytes(payload), manifest


# ---------------------------------------------------------------------------
# Bundle assembly
# ---------------------------------------------------------------------------

def write_or_check(path: Path, data: bytes, check: bool, mismatches: list[str]) -> None:
    if check:
        if not path.exists():
            mismatches.append(f"missing: {path.relative_to(REPO_ROOT)}")
        elif sha256(path.read_bytes()) != sha256(data):
            mismatches.append(f"stale: {path.relative_to(REPO_ROOT)}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def canonical_json(payload: dict[str, Any]) -> bytes:
    return (json.dumps(payload, indent=2, sort_keys=True) + "\n").encode()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rowplay-repo", required=True, type=Path)
    parser.add_argument(
        "--expected-commit",
        required=True,
        help="Exact RowPlay main commit the bundle is pinned to.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify the committed bundle matches the pinned tree without writing.",
    )
    arguments = parser.parse_args()
    repo: Path = arguments.rowplay_repo
    commit: str = arguments.expected_commit

    if not (repo / ".git").exists() and not (repo / "HEAD").exists():
        fail(f"{repo} is not a git repository")
    git_text(repo, "cat-file", "-e", f"{commit}^{{commit}}")
    resolved = git_text(repo, "rev-parse", f"{commit}^{{commit}}").strip()

    mismatches: list[str] = []
    check = arguments.check

    # Athlete artifacts, straight from the pinned tree.
    contract_blob = git_blob(repo, resolved, "static/replay-assets/rowplay-athlete-v4.contract.json")
    contract = json.loads(contract_blob)
    usdz_blob = git_blob(repo, resolved, "static/replay-assets/rowplay-athlete-v4.usdz")
    glb_blob = git_blob(repo, resolved, "static/replay-assets/rowplay-athlete-v4.glb")

    native = contract.get("nativeDerivativeArtifact", {})
    if native.get("sha256") != sha256(usdz_blob):
        fail("pinned USDZ does not match the contract's nativeDerivativeArtifact hash")
    web = contract.get("webRuntimeArtifact", {})
    if web.get("sha256") != sha256(glb_blob):
        fail("pinned GLB does not match the contract's webRuntimeArtifact hash")

    bones = contract.get("bones", {})
    if bones.get("semanticOrderedNames") != SEMANTIC_BONES:
        fail("contract semantic bone list drifted from the sync script's table")

    write_or_check(
        REFERENCE_ROOT / "athlete" / "rowplay-athlete-v4.usdz", usdz_blob, check, mismatches
    )
    write_or_check(
        REFERENCE_ROOT / "athlete" / "rowplay-athlete-v4.contract.json",
        contract_blob,
        check,
        mismatches,
    )

    athlete_source = {
        "pinnedCommit": resolved,
        "contractSchema": contract.get("schema"),
        "contractSchemaVersion": contract.get("schemaVersion"),
        "contractSha256": sha256(contract_blob),
        "glbSha256": sha256(glb_blob),
        "usdzSha256": sha256(usdz_blob),
        "semanticBoneCount": bones.get("semanticCount"),
        "helperCount": bones.get("helperCount"),
        "helperNames": bones.get("helperNames"),
        "totalBoneCount": bones.get("totalCount"),
        "provenance": contract.get("provenance"),
        "athleteAuthorship": (
            "RowPlay Studio does not author the athlete. The production "
            "anatomical athlete, semantic skeleton, grip helpers, clips and "
            "movement landmarks are owned by the merged upstream rowplay "
            "repository; Studio consumes them."
        ),
        "syncCommand": (
            "python3 script/sync_rowplay_reference.py "
            f"--rowplay-repo <rowplay> --expected-commit {resolved}"
        ),
    }
    write_or_check(
        REFERENCE_ROOT / "athlete" / "rowplay-athlete-source.json",
        canonical_json(athlete_source),
        check,
        mismatches,
    )

    # Motion table sampled from the pinned GLB clips.
    motion_bin, motion_manifest = sample_motion_table(glb_blob)
    motion_manifest["sourceCommit"] = resolved
    motion_manifest["sourceGlbSha256"] = sha256(glb_blob)
    motion_manifest["motionBinSha256"] = sha256(motion_bin)
    motion_manifest["motionBinByteCount"] = len(motion_bin)
    write_or_check(REFERENCE_ROOT / "motion" / "rowplay-motion.bin", motion_bin, check, mismatches)
    write_or_check(
        REFERENCE_ROOT / "motion" / "rowplay-motion-manifest.json",
        canonical_json(motion_manifest),
        check,
        mismatches,
    )

    # Environment material maps (CC0) from the pinned tree.
    environment_entries: list[dict[str, Any]] = []
    environments_readme = git_blob(
        repo, resolved, "static/replay-assets/environments/README.md"
    ).decode()
    for family in ENVIRONMENT_TEXTURE_FAMILIES:
        for suffix in TEXTURE_SUFFIXES:
            filename = _texture_filename(family, suffix)
            source_path = f"static/replay-assets/environments/{family}/{filename}"
            blob = git_blob(repo, resolved, source_path)
            write_or_check(
                REFERENCE_ROOT / "environment" / "textures" / family / filename,
                blob,
                check,
                mismatches,
            )
            environment_entries.append(
                {
                    "family": family,
                    "file": f"textures/{family}/{filename}",
                    "sourcePath": source_path,
                    "sha256": sha256(blob),
                    "byteCount": len(blob),
                }
            )
    environment_manifest = {
        "sourceCommit": resolved,
        "licence": "CC0 (see provenance)",
        "provenanceReadmeSha256": sha256(environments_readme.encode()),
        "textures": environment_entries,
    }
    write_or_check(
        REFERENCE_ROOT / "environment" / "environment-manifest.json",
        canonical_json(environment_manifest),
        check,
        mismatches,
    )

    # Equipment package: source GLB pinned here, conversion owned by Blender.
    rigs_blob = git_blob(repo, resolved, "static/replay-assets/rowplay-rigs-v3.glb")
    equipment_dir = REFERENCE_ROOT / "equipment"
    equipment_manifest_path = equipment_dir / "rowplay-equipment-manifest.json"
    if check:
        if not equipment_manifest_path.exists():
            mismatches.append("missing: equipment/rowplay-equipment-manifest.json (run convert_rowplay_equipment.py)")
        else:
            manifest = json.loads(equipment_manifest_path.read_text())
            if manifest.get("sourceCommit") != resolved:
                mismatches.append("equipment manifest pinned to a different commit")
            if manifest.get("sourceGlbSha256") != sha256(rigs_blob):
                mismatches.append("equipment manifest source GLB hash drifted")
            for entry in manifest.get("packages", []):
                package_path = equipment_dir / entry["file"]
                if not package_path.exists():
                    mismatches.append(f"missing: equipment/{entry['file']}")
                elif sha256(package_path.read_bytes()) != entry.get("sha256"):
                    mismatches.append(f"stale: equipment/{entry['file']}")
                contract_path = equipment_dir / entry["contractFile"]
                if not contract_path.exists():
                    mismatches.append(f"missing: equipment/{entry['contractFile']}")
                elif sha256(contract_path.read_bytes()) != entry.get("contractSha256"):
                    mismatches.append(f"stale: equipment/{entry['contractFile']}")
                else:
                    sidecar = json.loads(contract_path.read_text())
                    if sidecar.get("sourceCommit") != resolved:
                        mismatches.append(
                            f"equipment/{entry['contractFile']} pinned to a different commit"
                        )
                    if sidecar.get("sport") != entry.get("sport"):
                        mismatches.append(
                            f"equipment/{entry['contractFile']} sport does not match manifest"
                        )

    # Parity fixtures are generated into the Core test target by
    # export_rowplay_native_parity.mjs. Layers add those files independently,
    # so --check validates the fixtures present on the current branch without
    # requiring later stack outputs.
    parity_dir = REPO_ROOT / "Tests" / "RowPlayCoreTests" / "Fixtures"
    if check:
        expected_parity = [
            "replay-motion-graph-v4.json",
            "replay-current-main-motion.json",
            "replay-current-main-grips.json",
            "replay-current-main-equipment.json",
            "replay-current-main-2d.json",
        ]
        for name in expected_parity:
            fixture_path = parity_dir / name
            if not fixture_path.exists():
                continue
            fixture = json.loads(fixture_path.read_text())
            if fixture.get("sourceCommit") != resolved:
                mismatches.append(f"Tests/RowPlayCoreTests/Fixtures/{name} pinned to a different commit")

    # Top-level source manifest.
    source_manifest = {
        "pinnedRowPlayMainCommit": resolved,
        "upstreamRepository": "https://github.com/shenghaoc/rowplay",
        "consumptionStatement": (
            "RowPlay Studio consumes the production cross-platform replay "
            "reference owned by rowplay main; it does not independently "
            "redesign the athlete, mechanics, grips or visual contracts."
        ),
        "sourcePRLineage": [
            172, 173, 174, 175, 176, 178, 179, 180, 181, 191, 192, 193, 194,
        ],
        "artifacts": {
            "athleteContract": {
                "sourcePath": "static/replay-assets/rowplay-athlete-v4.contract.json",
                "sha256": sha256(contract_blob),
                "byteCount": len(contract_blob),
            },
            "athleteUsdz": {
                "sourcePath": "static/replay-assets/rowplay-athlete-v4.usdz",
                "sha256": sha256(usdz_blob),
                "byteCount": len(usdz_blob),
            },
            "athleteGlb": {
                "sourcePath": "static/replay-assets/rowplay-athlete-v4.glb",
                "sha256": sha256(glb_blob),
                "byteCount": len(glb_blob),
            },
            "equipmentSourceGlb": {
                "sourcePath": "static/replay-assets/rowplay-rigs-v3.glb",
                "sha256": sha256(rigs_blob),
                "byteCount": len(rigs_blob),
            },
        },
        "athlete": {
            "contractSchema": contract.get("schema"),
            "contractSchemaVersion": contract.get("schemaVersion"),
            "semanticBoneCount": bones.get("semanticCount"),
            "helperCount": bones.get("helperCount"),
            "totalBoneCount": bones.get("totalCount"),
            "materialRoleCount": len(contract.get("surfaces", [])),
        },
        "generationCommands": [
            "python3 script/sync_rowplay_reference.py --rowplay-repo <rowplay> "
            f"--expected-commit {resolved}",
            "<blender> --background --python script/convert_rowplay_equipment.py -- "
            f"--rowplay-repo <rowplay> --expected-commit {resolved}",
            "node script/export_rowplay_native_parity.mjs --rowplay-repo <rowplay> "
            f"--commit {resolved}",
        ],
        "runtimeDownloads": "none — every artifact ships in the app bundle",
    }
    write_or_check(
        REFERENCE_ROOT / "rowplay-source.json",
        canonical_json(source_manifest),
        check,
        mismatches,
    )

    if check:
        if mismatches:
            for line in mismatches:
                print(f"CHECK FAILED {line}", file=sys.stderr)
            raise SystemExit(1)
        print(f"reference bundle matches RowPlay {resolved}")
    else:
        print(f"reference bundle synced from RowPlay {resolved}")
        print(f"  motion table: {len(motion_bin)} bytes, {SAMPLES_PER_SPORT} phases/sport")


def _texture_filename(family: str, suffix: str) -> str:
    # snow-02's files drop the numeric suffix; every other family repeats
    # its directory name.
    if family == "snow-02":
        return f"snow-{suffix}"
    if family == "wood-floor":
        return f"wood-floor-{suffix}"
    return f"{family}-{suffix}"


if __name__ == "__main__":
    main()
