#!/usr/bin/env python3
"""
Deterministic Blender script: coherent athletic character via direct bmesh.

Each body segment is a tapered organic form built from circle cross-sections
bridged together, then bevelled and subdivided. Adjacent segments overlap at
joints so pivot rotation never exposes gaps. Clothing bridges the transitions.

Output: Sources/RowPlayStudio/Assets/athlete-character.usdz
"""

import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix

# ── Proportions ──────────────────────────────────────────────────────────────
HEAD_R = 0.115; HEAD_CENTER = Vector((0, 1.68, 0))
NECK_TOP = 1.54; NECK_BOT = 1.42
SHOULDER_Y = 1.40; SHOULDER_W = 0.185
HIP_Y = 0.88; HIP_W = 0.12
KNEE_Y = 0.44; ANKLE_Y = 0.06
ELBOW_Y = 1.17; WRIST_Y = 0.98
FOOT_Z = 0.06
SH_OL = 0.045; EL_OL = 0.035; HP_OL = 0.045; KN_OL = 0.040; AK_OL = 0.035

OUTPUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Sources", "RowPlayStudio", "Assets")
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "athlete-character.usdz")

SKIN = (0.79, 0.60, 0.45, 1.0); KIT = (0.12, 0.16, 0.19, 1.0)
SHORTS_CLR = (0.11, 0.14, 0.17, 1.0); SHOE = (0.08, 0.09, 0.10, 1.0)
HAIR = (0.14, 0.11, 0.09, 1.0)

def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

def make_material(name, color_rgba, roughness=0.7):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf: bsdf.inputs["Base Color"].default_value = color_rgba
    if bsdf: bsdf.inputs["Roughness"].default_value = roughness
    return mat

def apply_transform(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

def subdivide(obj, levels=2):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new(name="Subdiv", type='SUBSURF')
    mod.levels = levels; mod.render_levels = levels
    mod.subdivision_type = 'CATMULL_CLARK'
    bpy.ops.object.modifier_apply(modifier=mod.name)

def ellipse_profile(cx, cy, cz, rx, rz, segments=32):
    """Return list of (x,y,z) tuples forming an ellipse in the XZ plane at given Y."""
    pts = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        pts.append((cx + math.cos(a) * rx, cy, cz + math.sin(a) * rz))
    return pts

def tapered_segment(name, profiles, segments=32, bevel_r=0.006):
    """
    Build a mesh from stacked cross-section profiles.
    profiles: list of (center_xyz, radius_x, radius_z) tuples from bottom to top.
    Each profile defines a cross-section ellipse.
    """
    bm = bmesh.new()
    ring_verts = []
    for cx, cy, cz, rx, rz in profiles:
        ring = []
        for i in range(segments):
            a = 2 * math.pi * i / segments
            x = cx + math.cos(a) * rx
            z = cz + math.sin(a) * rz
            ring.append(bm.verts.new(Vector((x, cy, z))))
        ring_verts.append(ring)
    bm.verts.ensure_lookup_table()

    # Bridge adjacent rings
    for ri in range(len(ring_verts) - 1):
        a_ring = ring_verts[ri]
        b_ring = ring_verts[ri + 1]
        for i in range(segments):
            j = (i + 1) % segments
            # Create face between four vertices
            try:
                bm.faces.new((a_ring[i], a_ring[j], b_ring[j], b_ring[i]))
            except ValueError:
                pass  # face already exists

    # Cap top and bottom
    for ring in (ring_verts[0], ring_verts[-1]):
        try:
            bm.faces.new(list(reversed(ring)))
        except ValueError:
            pass

    # Bevel for organic roundness
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel_r,
                    offset_type='OFFSET', segments=2, profile=0.5)
    # Remove doubles
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0001)

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    subdivide(obj, 2)
    return obj


def sphere_segment(name, cx, cy, cz, rx, ry, rz, segments=32):
    """Build an ellipsoid mesh from stacked circular cross-sections."""
    bm = bmesh.new()
    ring_verts = []
    n_rings = 24
    for ri in range(n_rings + 1):
        t = ri / n_rings  # 0 = south pole, 1 = north pole
        phi = t * math.pi  # polar angle
        ring_y = cy - ry + 2 * ry * t
        ring_r_x = rx * math.sin(phi)
        ring_r_z = rz * math.sin(phi)
        ring = []
        for i in range(segments):
            a = 2 * math.pi * i / segments
            x = cx + math.cos(a) * ring_r_x
            z = cz + math.sin(a) * ring_r_z
            ring.append(bm.verts.new(Vector((x, ring_y, z))))
        ring_verts.append(ring)
    bm.verts.ensure_lookup_table()
    for ri in range(len(ring_verts) - 1):
        a_ring = ring_verts[ri]; b_ring = ring_verts[ri + 1]
        n = len(a_ring)
        for i in range(n):
            j = (i + 1) % n
            try:
                bm.faces.new((a_ring[i], a_ring[j], b_ring[j], b_ring[i]))
            except ValueError:
                pass
    # Remove doubles
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0001)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    subdivide(obj, 2)
    return obj


# ── Body Segments ────────────────────────────────────────────────────────────

def make_head():
    return sphere_segment("athlete-head",
                          HEAD_CENTER.x, HEAD_CENTER.y, HEAD_CENTER.z,
                          HEAD_R, HEAD_R * 1.18, HEAD_R * 0.95)

def make_neck():
    return tapered_segment("athlete-neck", [
        (0, NECK_TOP, 0.005, 0.048, 0.040),
        (0, (NECK_TOP + NECK_BOT) / 2, 0.008, 0.054, 0.044),
        (0, NECK_BOT, 0.010, 0.060, 0.048),
    ])

def make_torso():
    return tapered_segment("athlete-torso", [
        (0, HIP_Y - HP_OL, 0.010, 0.14, 0.12),
        (0, 0.90, 0.010, 0.15, 0.13),
        (0, 1.00, 0.010, 0.155, 0.14),
        (0, 1.10, 0.010, 0.16, 0.14),
        (0, 1.20, 0.010, 0.17, 0.14),
        (0, 1.30, 0.010, 0.18, 0.14),
        (0, 1.38, 0.010, 0.18, 0.14),
        (0, SHOULDER_Y + SH_OL, 0.010, 0.18, 0.14),
    ])

def make_upper_arm(side):
    sfx = "R" if side > 0 else "L"
    sx = side * SHOULDER_W
    return tapered_segment(f"athlete-upperArm-{sfx}", [
        (sx, ELBOW_Y - EL_OL, 0, 0.030, 0.024),
        (sx, (SHOULDER_Y + ELBOW_Y) / 2, 0, 0.036, 0.030),
        (sx, SHOULDER_Y + SH_OL, 0, 0.042, 0.034),
    ])

def make_forearm(side):
    sfx = "R" if side > 0 else "L"
    sx = side * SHOULDER_W
    return tapered_segment(f"athlete-forearm-{sfx}", [
        (sx, WRIST_Y, 0, 0.024, 0.018),
        (sx, (ELBOW_Y + WRIST_Y) / 2, 0, 0.030, 0.024),
        (sx, ELBOW_Y + EL_OL, 0, 0.034, 0.028),
    ])

def make_hand(side):
    sfx = "R" if side > 0 else "L"
    sx = side * SHOULDER_W
    return tapered_segment(f"athlete-hand-{sfx}", [
        (sx, WRIST_Y - 0.02, 0.08, 0.018, 0.018),
        (sx, WRIST_Y, 0.04, 0.024, 0.018),
        (sx, WRIST_Y + 0.02, 0.02, 0.026, 0.020),
    ])

def make_thigh(side):
    sfx = "R" if side > 0 else "L"
    lx = side * HIP_W
    return tapered_segment(f"athlete-thigh-{sfx}", [
        (lx, KNEE_Y - KN_OL, 0, 0.038, 0.032),
        (lx, (HIP_Y + KNEE_Y) / 2, 0, 0.050, 0.042),
        (lx, HIP_Y + HP_OL, 0, 0.058, 0.048),
    ])

def make_shin(side):
    sfx = "R" if side > 0 else "L"
    lx = side * HIP_W
    return tapered_segment(f"athlete-shin-{sfx}", [
        (lx, ANKLE_Y - AK_OL, 0, 0.028, 0.022),
        (lx, (KNEE_Y + ANKLE_Y) / 2, 0, 0.036, 0.030),
        (lx, KNEE_Y + KN_OL, 0, 0.042, 0.034),
    ])

def make_foot(side):
    sfx = "R" if side > 0 else "L"
    lx = side * HIP_W
    return tapered_segment(f"athlete-foot-{sfx}", [
        (lx, 0.00, FOOT_Z + 0.04, 0.022, 0.022),
        (lx, ANKLE_Y, FOOT_Z, 0.030, 0.024),
        (lx, ANKLE_Y + AK_OL, 0.01, 0.032, 0.026),
    ])


# ── Clothing ─────────────────────────────────────────────────────────────────

def make_shirt():
    return tapered_segment("athlete-shirt", [
        (0, HIP_Y + 0.12, 0.010, SHOULDER_W - 0.01, SHOULDER_W * 0.6),
        (0, SHOULDER_Y - 0.15, 0.008, SHOULDER_W + 0.02, SHOULDER_W * 0.7),
    ], bevel_r=0.02)

def make_shorts():
    return tapered_segment("athlete-shorts", [
        (0, HIP_Y - HP_OL * 2, 0.008, HIP_W + 0.01, HIP_W * 0.9),
        (0, HIP_Y + HP_OL, 0.005, HIP_W + 0.03, HIP_W * 1.1),
    ], bevel_r=0.02)

def make_shoe_mesh(side):
    sfx = "R" if side > 0 else "L"
    lx = side * HIP_W
    return tapered_segment(f"athlete-shoe-{sfx}", [
        (lx, ANKLE_Y - 0.01, FOOT_Z + 0.06, 0.020, 0.020),
        (lx, ANKLE_Y + 0.01, FOOT_Z, 0.028, 0.022),
        (lx, ANKLE_Y + AK_OL + 0.01, 0.01, 0.030, 0.024),
    ], bevel_r=0.01)


# ── Pivot alignment offsets ──────────────────────────────────────────────────
# Each segment mesh is built at its world-space position, then translated so
# its proximal joint sits at the object origin. RealityKit attaches each mesh
# at (0,0,0) relative to its pivot entity.

def proximal_offset(name):
    """Return (x, y, z) translation that moves the proximal joint to origin."""
    # Arms: lateral offset at shoulder
    if "upperArm-L" in name: return (-SHOULDER_W, SHOULDER_Y, 0)
    if "upperArm-R" in name: return ( SHOULDER_W, SHOULDER_Y, 0)
    if "forearm-L" in name:  return (-SHOULDER_W, ELBOW_Y, 0)
    if "forearm-R" in name:  return ( SHOULDER_W, ELBOW_Y, 0)
    if "hand-L" in name:     return (-SHOULDER_W, WRIST_Y, 0)
    if "hand-R" in name:     return ( SHOULDER_W, WRIST_Y, 0)
    # Legs: lateral offset at hip
    if "thigh-L" in name:    return (-HIP_W, HIP_Y, 0)
    if "thigh-R" in name:    return ( HIP_W, HIP_Y, 0)
    if "shin-L" in name:     return (-HIP_W, KNEE_Y, 0)
    if "shin-R" in name:     return ( HIP_W, KNEE_Y, 0)
    if "foot-L" in name:     return (-HIP_W, ANKLE_Y, 0)
    if "foot-R" in name:     return ( HIP_W, ANKLE_Y, 0)
    if "shoe-L" in name:     return (-HIP_W, ANKLE_Y, 0)
    if "shoe-R" in name:     return ( HIP_W, ANKLE_Y, 0)
    # Central body
    if "head" in name:       return (0, HEAD_CENTER.y, 0)
    if "neck" in name:       return (0, NECK_TOP, 0)
    if "torso" in name:      return (0, HIP_Y, 0)
    if "shirt" in name:      return (0, HIP_Y + 0.12, 0)
    if "shorts" in name:     return (0, HIP_Y, 0)
    return (0, 0, 0)

def translate_to_origin(obj):
    """Shift vertex positions so proximal joint is at origin."""
    ox, oy, oz = proximal_offset(obj.name)
    if ox == 0 and oy == 0 and oz == 0:
        return
    # Move vertices in mesh data
    for v in obj.data.vertices:
        v.co.x -= ox
        v.co.y -= oy
        v.co.z -= oz

# ── Main ────────────────────────────────────────────────────────────────────

def main():
    clear_scene()
    skin_mat = make_material("skin", SKIN, 0.74)
    kit_mat = make_material("kit", KIT, 0.70)
    shorts_mat = make_material("shorts", SHORTS_CLR, 0.70)
    shoe_mat = make_material("shoe", SHOE, 0.80)
    hair_mat = make_material("hair", HAIR, 0.80)

    segments = []
    clothing = []

    print("Head..."); segments.append(make_head())
    print("Neck..."); segments.append(make_neck())
    print("Torso..."); segments.append(make_torso())
    for side in (-1, 1):
        lbl = "R" if side > 0 else "L"
        print(f"Arm {lbl}...")
        segments.append(make_upper_arm(side))
        segments.append(make_forearm(side))
        segments.append(make_hand(side))
    for side in (-1, 1):
        lbl = "R" if side > 0 else "L"
        print(f"Leg {lbl}...")
        segments.append(make_thigh(side))
        segments.append(make_shin(side))
        segments.append(make_foot(side))

    print("Clothing...")
    shirt = make_shirt(); shirt.data.materials.append(kit_mat); clothing.append(shirt)
    shorts = make_shorts(); shorts.data.materials.append(shorts_mat); clothing.append(shorts)
    for side in (-1, 1):
        sfx = "R" if side > 0 else "L"
        s = make_shoe_mesh(side); s.data.materials.append(shoe_mat)
        clothing.append(s)

    # Center each mesh at its proximal pivot
    print("Aligning pivots...")
    all_objs = segments + clothing
    for obj in all_objs:
        translate_to_origin(obj)
        apply_transform(obj)

    # Material assignment
    mat_map = {"head": hair_mat, "neck": skin_mat, "torso": kit_mat,
               "upperArm": skin_mat, "forearm": skin_mat, "hand": skin_mat,
               "thigh": skin_mat, "shin": skin_mat, "foot": shoe_mat}
    for obj in segments:
        for key, mat in mat_map.items():
            if key in obj.name:
                if obj.data.materials: obj.data.materials[0] = mat
                else: obj.data.materials.append(mat)
                break

    empty = [o for o in all_objs if not o.data or len(o.data.vertices) == 0]
    if empty:
        print(f"WARNING: {len(empty)} empty: {[o.name for o in empty]}")

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    valid = [o for o in all_objs if o and o.data and len(o.data.vertices) > 0]
    for o in valid: o.select_set(True)
    if valid: bpy.context.view_layer.objects.active = valid[0]
    bpy.ops.wm.usd_export(
        filepath=OUTPUT_PATH, selected_objects_only=True,
        export_animation=False, export_hair=False,
        export_uvmaps=True, export_normals=True,
        export_materials=True, generate_preview_surface=True,
        convert_orientation=True)

    tv = sum(len(o.data.vertices) for o in valid)
    tf = sum(len(o.data.polygons) for o in valid)
    print(f"\nOK: {len(valid)} objects → {OUTPUT_PATH}")
    print(f"Total: {tv}v / {tf}f")
    for o in valid:
        # Show bounds to verify pivot alignment
        xs = [v.co.x for v in o.data.vertices]
        ys = [v.co.y for v in o.data.vertices]
        zs = [v.co.z for v in o.data.vertices]
        print(f"  {o.name}: {len(o.data.vertices)}v, "
              f"X[{min(xs):.3f}:{max(xs):.3f}] "
              f"Y[{min(ys):.3f}:{max(ys):.3f}] "
              f"Z[{min(zs):.3f}:{max(zs):.3f}]")

if __name__ == "__main__":
    main()
