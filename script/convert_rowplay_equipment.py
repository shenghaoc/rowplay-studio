#!/usr/bin/env python3
"""Convert the pinned RowPlay V3 equipment GLB into per-sport native USDZ.

Runs inside Blender (development time only — never at app runtime):

    "$BLENDER_BIN" --background --python script/convert_rowplay_equipment.py -- \
        --rowplay-repo /path/to/rowplay \
        --expected-commit <rowplay-main-sha> [--check]

Reads ``static/replay-assets/rowplay-rigs-v3.glb`` from the exact pinned Git
tree, splits it into the three sport packages, and exports one USDZ per sport
under ``Sources/RowPlayStudio/Resources/ReplayReference/equipment/`` together
with a sidecar node/part/material contract.  Geometry is converted, never
redesigned: transforms and bounds are preserved and the script fails on any
missing or duplicated required part.

USD prim names cannot contain ``:``, so exported object names replace ``:``
with ``_``; the sidecar contract records both the source and exported name for
every node so native lookups stay exact.
"""

import argparse
import hashlib
import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import bpy

from replay_reference_contract import (
    DOMAIN_TO_EQUIPMENT_SPORT,
    EQUIPMENT_SPORTS,
    validate_equipment_manifest,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
EQUIPMENT_ROOT = (
    REPO_ROOT / "Sources" / "RowPlayStudio" / "Resources" / "ReplayReference" / "equipment"
)

# Composite templates and their required parts, mirrored from the pinned
# RowPlay `scripts/validate-replay-assets.mjs`.
TEMPLATE_PARTS = {
    "equipment:row:boat-assembly": {
        "hull", "stern-deck", "bow-deck", "cockpit-tub", "bulkheads", "gunwales",
        "slide-rails", "accent-strakes", "foot-stretcher", "heel-cups",
        "stretcher-hardware", "riggers", "oarlocks", "keel-fin",
    },
    "equipment:row:seat-carriage": {"seat-pad", "seat-carriage", "seat-rollers", "seat-guides"},
    "equipment:row:oar-rig": {"shaft", "grip", "handle-cap", "collar", "blade-sleeve"},
    "equipment:ski:ski-assembly": {
        "base", "top-deck", "edge-left", "edge-right", "binding-plate",
        "binding-toe", "binding-heel", "tip-ridge",
    },
    "equipment:bike:wheel-assembly": {"tyre", "aero-rim", "hub", "brake-rotor", "spokes"},
    "equipment:bike:frame-assembly": {
        "main-triangle", "stays-and-fork", "cockpit", "brake-hoods", "brake-levers",
        "brake-calipers", "chain-and-cassette", "saddle", "seat-post", "fork-crown",
        "rear-axle", "front-axle",
    },
    "equipment:bike:drivetrain-assembly": {
        "chainring", "spider", "crank-arms", "clipless-pedals", "bottom-bracket",
    },
}

SPORT_TEMPLATES = {
    DOMAIN_TO_EQUIPMENT_SPORT["rower"]: [
        "equipment:row:boat-assembly",
        "equipment:row:seat-carriage",
        "equipment:row:oar-rig",
    ],
    DOMAIN_TO_EQUIPMENT_SPORT["skierg"]: ["equipment:ski:ski-assembly"],
    DOMAIN_TO_EQUIPMENT_SPORT["bike"]: [
        "equipment:bike:wheel-assembly",
        "equipment:bike:frame-assembly",
        "equipment:bike:drivetrain-assembly",
    ],
}

# Leaf slots each sport still consumes from the V3 file (SkiErg poles have
# no composite — the leaf shaft/grip/basket meshes are the authored pole
# geometry; the row blade leaf backs the oar spoon).
SPORT_LEAVES = {
    DOMAIN_TO_EQUIPMENT_SPORT["rower"]: ["equipment:row:blade"],
    DOMAIN_TO_EQUIPMENT_SPORT["skierg"]: [
        "equipment:ski:pole-shaft",
        "equipment:ski:pole-grip",
        "equipment:ski:pole-basket",
    ],
    DOMAIN_TO_EQUIPMENT_SPORT["bike"]: [],
}

OUTPUT_FILES = {
    DOMAIN_TO_EQUIPMENT_SPORT["rower"]: "rowplay-row-equipment.usdz",
    DOMAIN_TO_EQUIPMENT_SPORT["skierg"]: "rowplay-ski-equipment.usdz",
    DOMAIN_TO_EQUIPMENT_SPORT["bike"]: "rowplay-bike-equipment.usdz",
}


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def usd_safe(name: str) -> str:
    return name.replace(":", "_").replace("-", "_")


def parse_arguments():
    if "--" in sys.argv:
        arguments = sys.argv[sys.argv.index("--") + 1 :]
    else:
        arguments = []
    parser = argparse.ArgumentParser()
    parser.add_argument("--rowplay-repo", required=True, type=Path)
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--check", action="store_true")
    return parser.parse_args(arguments)


def extract_glb(repo: Path, commit: str, destination: Path) -> None:
    blob = subprocess.run(
        [
            "git", "-C", str(repo), "cat-file", "blob",
            f"{commit}:static/replay-assets/rowplay-rigs-v3.glb",
        ],
        check=True,
        capture_output=True,
    ).stdout
    destination.write_bytes(blob)


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def object_bounds(obj):
    coordinates = [obj.matrix_world @ v for v in [
        __import__("mathutils").Vector(corner) for corner in obj.bound_box
    ]]
    minimum = [min(c[i] for c in coordinates) for i in range(3)]
    maximum = [max(c[i] for c in coordinates) for i in range(3)]
    return {"min": minimum, "max": maximum}


def collect_hierarchy(root):
    nodes = [root]
    for child in root.children:
        nodes.extend(collect_hierarchy(child))
    return nodes


def main() -> None:
    arguments = parse_arguments()
    repo = arguments.rowplay_repo
    commit = arguments.expected_commit

    resolved = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", f"{commit}^{{commit}}"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()

    with tempfile.TemporaryDirectory() as scratch:
        glb_path = Path(scratch) / "rowplay-rigs-v3.glb"
        extract_glb(repo, resolved, glb_path)
        source_hash = sha256(glb_path)

        manifest_path = EQUIPMENT_ROOT / "rowplay-equipment-manifest.json"
        if arguments.check:
            if not manifest_path.exists():
                fail("equipment manifest missing — run without --check first")
            manifest = json.loads(manifest_path.read_text())
            errors = validate_equipment_manifest(
                manifest,
                EQUIPMENT_ROOT,
                expected_commit=resolved,
                expected_source_glb_sha256=source_hash,
            )
            if errors:
                fail("; ".join(errors))
            print(f"equipment packages match RowPlay {resolved}")
            return

        packages = []
        for sport in EQUIPMENT_SPORTS:
            templates = SPORT_TEMPLATES[sport]
            reset_scene()
            bpy.ops.import_scene.gltf(filepath=str(glb_path))
            all_objects = {obj.name: obj for obj in bpy.data.objects}

            keep_roots = []
            contract_nodes = []
            for template in templates:
                root = all_objects.get(template)
                if root is None:
                    fail(f"{sport}: composite root {template!r} missing from GLB")
                children = {}
                for child in collect_hierarchy(root):
                    if child is root:
                        continue
                    part = child.get("replayAssetPart") or child.name.split(":")[-1]
                    if part in children:
                        fail(f"{sport}: duplicated part {template}:{part}")
                    children[part] = child
                required = TEMPLATE_PARTS[template]
                missing = required - set(children)
                if missing:
                    fail(f"{sport}: {template} missing parts {sorted(missing)}")
                keep_roots.append(root)
                contract_nodes.append(
                    {
                        "kind": "composite",
                        "sourceName": template,
                        "exportedName": usd_safe(template),
                        "parts": [
                            {
                                "part": part,
                                "sourceName": child.name,
                                "exportedName": usd_safe(child.name),
                                "materialRole": child.get("replayMaterialRole")
                                or (child.active_material.get("replayMaterialRole")
                                    if child.active_material else None),
                                "bounds": object_bounds(child),
                            }
                            for part, child in sorted(children.items())
                        ],
                        "bounds": object_bounds(root),
                        "transform": [list(row) for row in root.matrix_world.row],
                    }
                )
            for leaf in SPORT_LEAVES[sport]:
                obj = all_objects.get(leaf)
                if obj is None:
                    fail(f"{sport}: leaf {leaf!r} missing from GLB")
                keep_roots.append(obj)
                contract_nodes.append(
                    {
                        "kind": "leaf",
                        "sourceName": leaf,
                        "exportedName": usd_safe(leaf),
                        "bounds": object_bounds(obj),
                    }
                )

            keep = set()
            for root in keep_roots:
                keep.update(collect_hierarchy(root))
            for obj in list(bpy.data.objects):
                if obj not in keep:
                    bpy.data.objects.remove(obj, do_unlink=True)

            # USD prim names cannot carry ':' or '-'; rename in place and
            # record the mapping in the sidecar contract above.
            for obj in bpy.data.objects:
                obj.name = usd_safe(obj.name)
                if obj.data is not None:
                    obj.data.name = usd_safe(obj.data.name)

            output = EQUIPMENT_ROOT / OUTPUT_FILES[sport]
            output.parent.mkdir(parents=True, exist_ok=True)
            bpy.ops.wm.usd_export(
                filepath=str(output),
                selected_objects_only=False,
                export_animation=False,
                export_materials=True,
                use_instancing=False,
            )
            if not output.exists():
                fail(f"{sport}: USD export produced no file")

            sidecar = {
                "sport": sport,
                "sourceCommit": resolved,
                "sourceGlbSha256": source_hash,
                "nodes": contract_nodes,
            }
            sidecar_path = EQUIPMENT_ROOT / f"rowplay-{sport}-equipment.contract.json"
            sidecar_path.write_text(json.dumps(sidecar, indent=2, sort_keys=True) + "\n")

            packages.append(
                {
                    "sport": sport,
                    "file": OUTPUT_FILES[sport],
                    "sha256": sha256(output),
                    "byteCount": output.stat().st_size,
                    "contractFile": sidecar_path.name,
                    "contractSha256": sha256(sidecar_path),
                }
            )
            print(f"exported {sport}: {output.name} ({output.stat().st_size} bytes)")

        manifest = {
            "sourceCommit": resolved,
            "sourceGlbPath": "static/replay-assets/rowplay-rigs-v3.glb",
            "sourceGlbSha256": source_hash,
            "converter": "Blender " + bpy.app.version_string,
            "geometryPolicy": (
                "converted from the pinned RowPlay V3 GLB with names, "
                "transforms and bounds preserved; no geometry redesign"
            ),
            "packages": packages,
        }
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        print(f"equipment manifest written for RowPlay {resolved}")


if __name__ == "__main__":
    main()
