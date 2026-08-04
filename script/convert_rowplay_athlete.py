#!/usr/bin/env python3
"""Build the native V4 athlete material derivative from pinned RowPlay.

Run inside Blender at development time (never in the app):

    "$BLENDER_BIN" --background --python script/convert_rowplay_athlete.py -- \
        --rowplay-repo /path/to/rowplay \
        --expected-commit <rowplay-main-sha> [--check]

The pinned GLB intentionally contains one skinned primitive whose reviewed
surface regions are encoded as vertex colours. Blender's stock USD exporter
does not preserve that colour attribute in the upstream USDZ, so a direct
native load collapses the athlete to one grey material. This converter keeps
the pinned USDZ's mesh, skeleton, contacts, and animation intact, partitions
its triangles into the eight contract surface roles by the same
majority-vertex rule as RowPlay, and authors eight USD material subsets. It
does not remodel, reskin, or re-export the athlete geometry.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

import bpy
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, Vt


REPO_ROOT = Path(__file__).resolve().parent.parent
ATHLETE_ROOT = (
    REPO_ROOT / "Sources" / "RowPlayStudio" / "Resources" / "ReplayReference" / "athlete"
)
OUTPUT_PATH = ATHLETE_ROOT / "rowplay-athlete-v4-native.usdz"
MANIFEST_PATH = ATHLETE_ROOT / "rowplay-athlete-v4-native.json"
SOURCE_GLB_PATH = "static/replay-assets/rowplay-athlete-v4.glb"
SOURCE_USDZ_PATH = "static/replay-assets/rowplay-athlete-v4.usdz"
SOURCE_CONTRACT_PATH = "static/replay-assets/rowplay-athlete-v4.contract.json"


# Contract name, RowPlay runtime name, authored fallback base colour, and the
# regional vertex-colour palette copied from pinned renderer3dV4Assets.ts.
SURFACES = [
    (
        "athlete-skin",
        "skin",
        (0.69, 0.405, 0.285, 1.0),
        [
            (0.64, 0.39, 0.285), (0.73, 0.49, 0.37), (0.69, 0.405, 0.285),
            (0.49, 0.285, 0.225), (0.58, 0.34, 0.245), (0.68, 0.43, 0.32),
            (0.72, 0.48, 0.36), (0.82, 0.6, 0.48),
        ],
    ),
    (
        "athlete-fabric",
        "jersey",
        (0.18, 0.28, 0.52, 1.0),
        [
            (0.09, 0.14, 0.28), (0.035, 0.055, 0.12), (0.18, 0.28, 0.52),
            (0.055, 0.075, 0.14), (0.028, 0.038, 0.075), (0.095, 0.125, 0.22),
            (0.2, 0.18, 0.45), (0.11, 0.12, 0.28), (0.34, 0.36, 0.66),
        ],
    ),
    (
        "athlete-shorts",
        "lower",
        (0.075, 0.12, 0.15, 1.0),
        [
            (0.035, 0.045, 0.07), (0.065, 0.08, 0.12), (0.075, 0.12, 0.15),
            (0.04, 0.075, 0.095), (0.13, 0.19, 0.22), (0.08, 0.09, 0.16),
            (0.14, 0.16, 0.28), (0.22, 0.36, 0.44), (0.14, 0.24, 0.3),
            (0.38, 0.52, 0.6),
        ],
    ),
    (
        "athlete-footwear",
        "footwear",
        (0.24, 0.28, 0.32, 1.0),
        [
            (0.24, 0.28, 0.32), (0.045, 0.055, 0.07), (0.018, 0.024, 0.032),
            (0.62, 0.65, 0.68), (0.07, 0.085, 0.1), (0.025, 0.032, 0.04),
            (0.88, 0.9, 0.93), (0.12, 0.15, 0.19), (0.06, 0.08, 0.1),
        ],
    ),
    (
        "athlete-hair",
        "hair",
        (0.18, 0.075, 0.028, 1.0),
        [
            (0.13, 0.035, 0.008), (0.145, 0.041, 0.01), (0.16, 0.05, 0.013),
            (0.045, 0.009, 0.003), (0.24, 0.075, 0.018), (0.18, 0.075, 0.028),
            (0.075, 0.026, 0.012), (0.29, 0.13, 0.052), (0.3, 0.17, 0.09),
            (0.16, 0.075, 0.035), (0.39, 0.22, 0.105), (0.22, 0.13, 0.075),
            (0.13, 0.085, 0.055), (0.08, 0.09, 0.12),
        ],
    ),
    (
        "athlete-trim",
        "trim",
        (0.26, 0.38, 0.72, 1.0),
        [(0.26, 0.38, 0.72), (0.18, 0.23, 0.39), (0.42, 0.38, 0.78)],
    ),
    (
        "athlete-eye",
        "eye",
        (0.86, 0.82, 0.75, 1.0),
        [
            (0.35, 0.2, 0.14), (0.24, 0.1, 0.035), (0.075, 0.028, 0.012),
            (0.035, 0.018, 0.012), (0.86, 0.82, 0.75), (0.73, 0.69, 0.62),
            (0.88, 0.845, 0.78), (0.94, 0.97, 1.0),
        ],
    ),
    (
        "athlete-face-detail",
        "face-detail",
        (0.29, 0.12, 0.09, 1.0),
        [(0.25, 0.13, 0.08), (0.44, 0.24, 0.17), (0.29, 0.12, 0.09), (0.19, 0.075, 0.045)],
    ),
]


def fail(message: str) -> "None":
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def parse_arguments() -> argparse.Namespace:
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--rowplay-repo", required=True, type=Path)
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--check", action="store_true")
    return parser.parse_args(arguments)


def git_blob(repo: Path, commit: str, source_path: str) -> bytes:
    return subprocess.run(
        ["git", "-C", str(repo), "cat-file", "blob", f"{commit}:{source_path}"],
        check=True,
        capture_output=True,
    ).stdout


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def srgb_to_linear(value: float) -> float:
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def color_distance(colour: tuple[float, float, float], swatch: tuple[float, float, float]) -> float:
    direct = sum((colour[index] - swatch[index]) ** 2 for index in range(3))
    linear = sum(
        (colour[index] - srgb_to_linear(swatch[index])) ** 2 for index in range(3)
    )
    return min(direct, linear)


def role_index(colour: tuple[float, float, float]) -> int:
    result = 1  # jersey is the pinned safe fallback
    best_distance = math.inf
    for index, (_, _, _, palette) in enumerate(SURFACES):
        for swatch in palette:
            distance = color_distance(colour, swatch)
            if distance < best_distance:
                best_distance = distance
                result = index
    return result


def imported_athlete_mesh() -> bpy.types.Object:
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        fail(f"expected one armature, received {len(armatures)}")
    armature = armatures[0]
    candidates = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "MESH"
        and any(modifier.type == "ARMATURE" and modifier.object == armature for modifier in obj.modifiers)
    ]
    if len(candidates) != 1:
        fail(f"expected one armature-bound athlete mesh, received {len(candidates)}")
    return candidates[0]


def classify_surface_faces(
    mesh_object: bpy.types.Object,
) -> tuple[list[list[int]], list[tuple[int, int, int]]]:
    mesh = mesh_object.data
    colour_attribute = mesh.color_attributes.active_color
    if colour_attribute is None or colour_attribute.domain != "CORNER":
        fail("athlete mesh requires a corner-domain vertex-colour attribute")
    if len(colour_attribute.data) != len(mesh.loops):
        fail("athlete colour data does not match its loop count")

    faces = [[] for _ in SURFACES]
    topology = []
    for polygon in mesh.polygons:
        roles = []
        for loop_index in polygon.loop_indices:
            colour = colour_attribute.data[loop_index].color_srgb
            roles.append(role_index((colour[0], colour[1], colour[2])))
        if len(roles) != 3:
            fail("production athlete must remain triangulated")
        topology.append(tuple(polygon.vertices))
        first, second, third = roles
        selected = first if first == second or first == third else second if second == third else first
        faces[selected].append(polygon.index)
    if any(not indices for indices in faces):
        missing = [SURFACES[index][1] for index, indices in enumerate(faces) if not indices]
        fail(f"surface partition produced empty roles: {missing}")
    return faces, topology


def author_surface_subsets(
    source_usdz: Path,
    stage_path: Path,
    face_indices: list[list[int]],
    glb_topology: list[tuple[int, int, int]],
    expected_vertex_count: int,
    expected_triangle_count: int,
) -> None:
    with zipfile.ZipFile(source_usdz) as archive:
        root_layers = [name for name in archive.namelist() if name.endswith((".usd", ".usda", ".usdc"))]
        if len(root_layers) != 1:
            fail(f"expected one USDZ root layer, received {root_layers}")
        stage_path.write_bytes(archive.read(root_layers[0]))

    stage = Usd.Stage.Open(str(stage_path))
    if stage is None:
        fail("could not open the pinned USDZ root layer")
    mesh_prims = [prim for prim in stage.Traverse() if prim.IsA(UsdGeom.Mesh)]
    if len(mesh_prims) != 1:
        fail(f"expected one USD mesh, received {len(mesh_prims)}")
    mesh = UsdGeom.Mesh(mesh_prims[0])
    face_counts = mesh.GetFaceVertexCountsAttr().Get()
    face_vertices = mesh.GetFaceVertexIndicesAttr().Get()
    points = mesh.GetPointsAttr().Get()
    if len(face_counts) != expected_triangle_count:
        fail(f"pinned USDZ triangle count drifted: {len(face_counts)}")
    if len(face_counts) != sum(len(indices) for indices in face_indices):
        fail("GLB and USDZ triangle counts differ")
    if any(count != 3 for count in face_counts):
        fail("pinned USDZ athlete must remain triangulated")
    if len(points) != expected_vertex_count:
        fail(f"pinned USDZ vertex count drifted: {len(points)}")
    if len(glb_topology) != len(face_counts) or len(face_vertices) != len(face_counts) * 3:
        fail("GLB and USDZ topology layouts differ")
    for face_index, glb_triangle in enumerate(glb_topology):
        offset = face_index * 3
        usdz_triangle = tuple(face_vertices[offset : offset + 3])
        if set(glb_triangle) != set(usdz_triangle):
            fail(f"GLB and USDZ face order diverged at triangle {face_index}")

    for child in list(mesh.GetPrim().GetChildren()):
        if child.IsA(UsdGeom.Subset):
            stage.RemovePrim(child.GetPath())

    materials_root = Sdf.Path("/RowPlayV4Athlete/_materials")
    existing_material = materials_root.AppendChild("Material_0")
    if stage.GetPrimAtPath(existing_material):
        stage.RemovePrim(existing_material)

    material_binding = UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim())
    material_binding.GetDirectBindingRel().ClearTargets(True)
    materials = []
    for contract_role, role, base_colour, _ in SURFACES:
        material_path = materials_root.AppendChild(f"rowplay_v4_{role.replace('-', '_')}")
        material = UsdShade.Material.Define(stage, material_path)
        material.GetPrim().SetCustomDataByKey("replayMaterialRole", contract_role)
        shader = UsdShade.Shader.Define(stage, material_path.AppendChild("PreviewSurface"))
        shader.CreateIdAttr("UsdPreviewSurface")
        shader.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(
            Gf.Vec3f(*base_colour[:3])
        )
        shader.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.72)
        shader.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0.0)
        material.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(), "surface")
        materials.append(material)

    material_binding.Bind(materials[0])
    for index, ((_, role, _, _), material, indices) in enumerate(
        zip(SURFACES, materials, face_indices, strict=True)
    ):
        subset = UsdGeom.Subset.CreateGeomSubset(
            mesh,
            f"surface_{index:02d}_{role.replace('-', '_')}",
            UsdGeom.Tokens.face,
            Vt.IntArray(indices),
            "materialBind",
        )
        subset.GetPrim().SetCustomDataByKey("replayMaterialRole", SURFACES[index][0])
        UsdShade.MaterialBindingAPI.Apply(subset.GetPrim()).Bind(material)
    UsdGeom.Subset.SetFamilyType(mesh, "materialBind", UsdGeom.Tokens.partition)
    stage.GetRootLayer().Save()


def write_deterministic_usdz(stage_path: Path, source_usdz: Path, output: Path) -> None:
    with zipfile.ZipFile(source_usdz) as source:
        source_entries = {
            info.filename: source.read(info.filename)
            for info in source.infolist()
            if not info.is_dir() and not info.filename.endswith((".usd", ".usda", ".usdc"))
        }
    entries = [("rowplay-athlete-v4-native.usdc", stage_path.read_bytes())]
    entries.extend(sorted(source_entries.items()))

    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_STORED, allowZip64=False) as archive:
        for filename, payload in entries:
            info = zipfile.ZipInfo(filename, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            data_offset_without_extra = archive.fp.tell() + 30 + len(filename.encode("utf-8"))
            padding = (-data_offset_without_extra) % 64
            if 0 < padding < 4:
                padding += 64
            if padding:
                info.extra = struct.pack("<HH", 0xFFFF, padding - 4) + bytes(padding - 4)
            archive.writestr(info, payload)

    validation = subprocess.run(
        ["/usr/bin/usdchecker", "--arkit", str(output)],
        capture_output=True,
        text=True,
    )
    if validation.returncode != 0:
        fail(f"USDZ compliance check failed: {validation.stderr.strip()}")


def validate_manifest(
    manifest: dict,
    resolved: str,
    glb_hash: str,
    usdz_hash: str,
    contract_hash: str,
) -> None:
    expected_roles = [contract_role for contract_role, _, _, _ in SURFACES]
    if manifest.get("schema") != "rowplay.replay.athlete-native.v1":
        fail("native athlete manifest schema mismatch")
    if manifest.get("sourceCommit") != resolved:
        fail("native athlete manifest pinned to a different commit")
    if manifest.get("sourceGlbSha256") != glb_hash:
        fail("native athlete manifest GLB hash mismatch")
    if manifest.get("sourceUsdzSha256") != usdz_hash:
        fail("native athlete manifest source USDZ hash mismatch")
    if manifest.get("sourceContractSha256") != contract_hash:
        fail("native athlete manifest contract hash mismatch")
    if manifest.get("surfaceRoles") != expected_roles:
        fail("native athlete surface role order mismatch")
    if manifest.get("skinnedMeshCount") != 1 or manifest.get("materialSlotCount") != 8:
        fail("native athlete mesh/material contract mismatch")
    if not OUTPUT_PATH.exists():
        fail("native athlete USDZ is missing")
    if manifest.get("runtimeUsdzSha256") != sha256(OUTPUT_PATH):
        fail("native athlete USDZ hash mismatch")
    if manifest.get("runtimeUsdzByteCount") != OUTPUT_PATH.stat().st_size:
        fail("native athlete USDZ byte count mismatch")


def main() -> None:
    arguments = parse_arguments()
    resolved = subprocess.run(
        ["git", "-C", str(arguments.rowplay_repo), "rev-parse", f"{arguments.expected_commit}^{{commit}}"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    glb_blob = git_blob(arguments.rowplay_repo, resolved, SOURCE_GLB_PATH)
    usdz_blob = git_blob(arguments.rowplay_repo, resolved, SOURCE_USDZ_PATH)
    contract_blob = git_blob(arguments.rowplay_repo, resolved, SOURCE_CONTRACT_PATH)
    glb_hash = sha256_bytes(glb_blob)
    usdz_hash = sha256_bytes(usdz_blob)
    contract_hash = sha256_bytes(contract_blob)
    contract = json.loads(contract_blob)
    mesh_contract = contract.get("mesh", {})
    expected_vertex_count = mesh_contract.get("vertices")
    expected_triangle_count = mesh_contract.get("triangles")
    if not isinstance(expected_vertex_count, int) or not isinstance(expected_triangle_count, int):
        fail("pinned athlete contract mesh counts are missing")
    contract_roles = {entry.get("role") for entry in contract.get("surfaces", [])}
    expected_roles = {entry[0] for entry in SURFACES}
    if contract_roles != expected_roles:
        fail("pinned athlete contract surface roles drifted")
    web_hash = contract.get("webRuntimeArtifact", {}).get("sha256")
    if web_hash != glb_hash:
        fail("pinned athlete GLB does not match its contract hash")
    native_source = contract.get("nativeDerivativeArtifact", {})
    if native_source.get("sha256") != usdz_hash or native_source.get("byteCount") != len(usdz_blob):
        fail("pinned athlete USDZ does not match its contract hash and byte count")

    if arguments.check:
        if not MANIFEST_PATH.exists():
            fail("native athlete manifest is missing; run without --check first")
        validate_manifest(
            json.loads(MANIFEST_PATH.read_text()),
            resolved,
            glb_hash,
            usdz_hash,
            contract_hash,
        )
        print(f"native athlete material derivative matches RowPlay {resolved}")
        return

    with tempfile.TemporaryDirectory() as scratch:
        scratch_root = Path(scratch)
        glb_path = Path(scratch) / "rowplay-athlete-v4.glb"
        source_usdz = scratch_root / "rowplay-athlete-v4.usdz"
        stage_path = scratch_root / "rowplay-athlete-v4-native.usdc"
        glb_path.write_bytes(glb_blob)
        source_usdz.write_bytes(usdz_blob)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        result = bpy.ops.import_scene.gltf(filepath=str(glb_path))
        if "FINISHED" not in result:
            fail(f"GLB import failed: {result}")

        athlete = imported_athlete_mesh()
        surface_faces, glb_topology = classify_surface_faces(athlete)
        if len(athlete.data.vertices) != expected_vertex_count:
            fail(f"pinned GLB vertex count drifted: {len(athlete.data.vertices)}")
        if len(athlete.data.polygons) != expected_triangle_count:
            fail(f"pinned GLB triangle count drifted: {len(athlete.data.polygons)}")
        # The source Icosphere is a non-contract authoring helper. Keep the
        # armature, contacts, root extras and animation actions only.
        for obj in list(bpy.context.scene.objects):
            if obj.type == "MESH" and obj is not athlete:
                if obj.vertex_groups or obj.name != "Icosphere":
                    fail(f"unexpected unskinned mesh: {obj.name}")
                bpy.data.objects.remove(obj, do_unlink=True)

        ATHLETE_ROOT.mkdir(parents=True, exist_ok=True)
        author_surface_subsets(
            source_usdz,
            stage_path,
            surface_faces,
            glb_topology,
            expected_vertex_count,
            expected_triangle_count,
        )
        write_deterministic_usdz(stage_path, source_usdz, OUTPUT_PATH)

    manifest = {
        "schema": "rowplay.replay.athlete-native.v1",
        "sourceCommit": resolved,
        "sourceGlbPath": SOURCE_GLB_PATH,
        "sourceGlbSha256": glb_hash,
        "sourceUsdzPath": SOURCE_USDZ_PATH,
        "sourceUsdzSha256": usdz_hash,
        "sourceContractPath": SOURCE_CONTRACT_PATH,
        "sourceContractSha256": contract_hash,
        "runtimeUsdzFile": OUTPUT_PATH.name,
        "runtimeUsdzSha256": sha256(OUTPUT_PATH),
        "runtimeUsdzByteCount": OUTPUT_PATH.stat().st_size,
        "converter": f"Blender {bpy.app.version_string} with OpenUSD {Usd.GetVersion()}",
        "conversionScript": "script/convert_rowplay_athlete.py",
        "geometryPolicy": (
            "pinned USDZ mesh, skeleton, contacts, and animation retained exactly at "
            "the authored-value level; material subsets alone are derived from the "
            "pinned GLB reviewed vertex colours; no remodel, reskin, or geometry re-export"
        ),
        "surfacePartition": "majority vertex-colour role per triangle",
        "surfaceRoles": [entry[0] for entry in SURFACES],
        "runtimeMaterialNames": [f"rowplay-v4-{entry[1]}" for entry in SURFACES],
        "surfaceTriangleCounts": {
            SURFACES[index][0]: len(indices)
            for index, indices in enumerate(surface_faces)
        },
        "skinnedMeshCount": 1,
        "materialSlotCount": len(SURFACES),
        "runtimeDownloads": "none",
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    validate_manifest(manifest, resolved, glb_hash, usdz_hash, contract_hash)
    print(
        f"exported {OUTPUT_PATH.name}: {OUTPUT_PATH.stat().st_size} bytes, "
        f"sha256 {manifest['runtimeUsdzSha256']}"
    )


if __name__ == "__main__":
    main()
