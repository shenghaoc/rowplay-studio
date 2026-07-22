#!/usr/bin/env python3
"""Generate the small, original Phase 11 replay asset package.

The generator deliberately uses only the Python standard library.  It writes
plain-text USDA so every bundled mesh, material, budget and contract fact can
be reviewed in source control.  It never downloads source material or contacts
the network.

Run from the repository root:

    python3 script/generate_replay_assets.py
    python3 script/generate_replay_assets.py --check
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Sequence


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
RESOURCE_DIRECTORY = REPOSITORY_ROOT / "Sources" / "RowPlayStudio" / "Resources" / "Replay3D"
CONTRACT_PATH = REPOSITORY_ROOT / "Tests" / "RowPlayStudioTests" / "Fixtures" / "replay-asset-contract.json"
PROVENANCE_PATH = RESOURCE_DIRECTORY / "ASSET_PROVENANCE.md"

# This is intentionally a recorded fixed value even though the current mesh
# construction is formula-only.  It makes it explicit that no hidden random
# source can affect a generated asset.
FIXED_SEED = 20260721
RIG_TRIANGLE_CEILING = 18_000
ENVIRONMENT_TRIANGLE_CEILING = 30_000
COMBINED_BYTE_LIMIT_EXCLUSIVE = 15 * 1024 * 1024
CONTRACT_SCHEMA_VERSION = 1

Vec3 = tuple[float, float, float]


@dataclass(frozen=True)
class Mesh:
    """A triangular mesh expressed entirely in local node coordinates."""

    points: tuple[Vec3, ...]
    faces: tuple[tuple[int, int, int], ...]


@dataclass(frozen=True)
class Component:
    """A named mesh child of a pivotable asset node."""

    name: str
    mesh: Mesh
    material: str


@dataclass(frozen=True)
class AssetPlan:
    filename: str
    sport: str
    kind: str
    root_name: str
    required_nodes: tuple[str, ...]
    node_components: tuple[tuple[str, tuple[Component, ...]], ...]
    materials: tuple[str, ...]
    triangle_ceiling: int


# Athlete body parts are intentionally absent. The production athlete is the
# upstream RowPlay V4 USDZ (see script/sync_rowplay_athlete.py). Low quality and
# total package failure continue to use the lightweight procedural athlete.
SPORT_RIG_NODES = {
    "rower": (
        "visual-hull",
        "visual-deck-stripe",
        "visual-footplate",
        "visual-rail",
        "visual-seat",
        "visual-handle",
        "visual-oar-port",
        "visual-oar-starboard",
    ),
    "skierg": (
        "visual-post-L",
        "visual-post-R",
        "visual-topBar",
        "visual-platform",
        "visual-handle-L",
        "visual-handle-R",
        "visual-pole-L",
        "visual-pole-R",
        "visual-cable",
    ),
    "bike": (
        "visual-wheel-front",
        "visual-wheel-rear",
        "visual-downTube",
        "visual-seatTube",
        "visual-topTube",
        "visual-cranks",
        "visual-chainRing",
        "visual-pedal-L",
        "visual-pedal-R",
        "visual-handlebar",
        "visual-saddle",
    ),
}

ENVIRONMENT_NODES = (
    "environment-root",
    "environment-ground",
    "environment-props",
)

RIG_MATERIALS = (
    "accent",
    "metal",
    "rubber",
)

ENVIRONMENT_MATERIALS = {
    "rower": ("water", "shore", "foliage", "accent", "metal"),
    "skierg": ("snow", "ice", "foliage", "accent", "metal"),
    "bike": ("asphalt", "concrete", "accent", "metal", "foliage"),
}

MATERIAL_VALUES: dict[str, tuple[Vec3, float, float]] = {
    # Category: (base colour, metallic, roughness).  These use the standard
    # UsdPreviewSurface PBR inputs rather than baked lighting or textures.
    # Athlete skin/hair/kit/shoe materials live on the upstream V4 athlete, not
    # in these native equipment/environment packages.
    "accent": ((0.12, 0.62, 0.82), 0.08, 0.42),
    "metal": ((0.46, 0.51, 0.56), 0.82, 0.27),
    "rubber": ((0.035, 0.045, 0.055), 0.0, 0.89),
    "water": ((0.05, 0.38, 0.53), 0.05, 0.22),
    "shore": ((0.34, 0.30, 0.20), 0.0, 0.91),
    "foliage": ((0.07, 0.29, 0.16), 0.0, 0.84),
    "snow": ((0.88, 0.94, 0.98), 0.0, 0.55),
    "ice": ((0.44, 0.77, 0.86), 0.1, 0.28),
    "asphalt": ((0.12, 0.14, 0.16), 0.0, 0.92),
    "concrete": ((0.42, 0.45, 0.48), 0.05, 0.76),
}


def finite(value: float) -> float:
    """Fail fast rather than serialising a non-finite USD value."""

    if not math.isfinite(value):
        raise ValueError(f"non-finite generated value: {value!r}")
    return value


def vector_add(point: Vec3, offset: Vec3) -> Vec3:
    return tuple(finite(point[index] + offset[index]) for index in range(3))  # type: ignore[return-value]


def translated(mesh: Mesh, offset: Vec3) -> Mesh:
    return Mesh(tuple(vector_add(point, offset) for point in mesh.points), mesh.faces)


def scaled(mesh: Mesh, scale: Vec3) -> Mesh:
    return Mesh(
        tuple(
            tuple(finite(point[index] * scale[index]) for index in range(3))  # type: ignore[arg-type]
            for point in mesh.points
        ),
        mesh.faces,
    )


def rotate_axis(mesh: Mesh, axis: str) -> Mesh:
    """Rotate a y-axis primitive to an x or z axis without node transforms."""

    def rotate(point: Vec3) -> Vec3:
        x, y, z = point
        if axis == "y":
            return point
        if axis == "x":
            return (y, x, z)
        if axis == "z":
            return (x, z, y)
        raise ValueError(f"unsupported axis: {axis}")

    return Mesh(tuple(rotate(point) for point in mesh.points), mesh.faces)


def box(width: float, height: float, depth: float, center: Vec3 = (0.0, 0.0, 0.0)) -> Mesh:
    half_width, half_height, half_depth = width / 2, height / 2, depth / 2
    points = (
        (-half_width, -half_height, -half_depth),
        (half_width, -half_height, -half_depth),
        (half_width, -half_height, half_depth),
        (-half_width, -half_height, half_depth),
        (-half_width, half_height, -half_depth),
        (half_width, half_height, -half_depth),
        (half_width, half_height, half_depth),
        (-half_width, half_height, half_depth),
    )
    faces = (
        (0, 2, 1), (0, 3, 2),  # bottom
        (4, 5, 6), (4, 6, 7),  # top
        (0, 1, 5), (0, 5, 4),  # back
        (1, 2, 6), (1, 6, 5),  # right
        (2, 3, 7), (2, 7, 6),  # front
        (3, 0, 4), (3, 4, 7),  # left
    )
    return translated(Mesh(points, faces), center)


def tapered_cylinder(
    height: float,
    radius_bottom: float,
    radius_top: float,
    *,
    segments: int = 12,
    axis: str = "y",
    center: Vec3 = (0.0, 0.0, 0.0),
) -> Mesh:
    if segments < 3:
        raise ValueError("a cylinder needs at least three segments")
    points: list[Vec3] = []
    for y, radius in ((-height / 2, radius_bottom), (height / 2, radius_top)):
        for index in range(segments):
            angle = 2 * math.pi * index / segments
            points.append((radius * math.cos(angle), y, radius * math.sin(angle)))
    faces: list[tuple[int, int, int]] = []
    bottom_start = 0
    top_start = segments
    for index in range(segments):
        next_index = (index + 1) % segments
        faces.append((bottom_start, bottom_start + next_index, bottom_start + index))
        faces.append((top_start, top_start + index, top_start + next_index))
        faces.append((bottom_start + index, bottom_start + next_index, top_start + next_index))
        faces.append((bottom_start + index, top_start + next_index, top_start + index))
    return translated(rotate_axis(Mesh(tuple(points), tuple(faces)), axis), center)


def ellipsoid(
    radius_x: float,
    radius_y: float,
    radius_z: float,
    *,
    longitude_segments: int = 12,
    latitude_segments: int = 7,
    center: Vec3 = (0.0, 0.0, 0.0),
) -> Mesh:
    """Low-poly rounded surface with one vertex per pole (no degenerate faces)."""

    if longitude_segments < 3 or latitude_segments < 3:
        raise ValueError("an ellipsoid needs at least three latitude/longitude segments")
    points: list[Vec3] = [(0.0, -radius_y, 0.0)]
    for latitude in range(1, latitude_segments):
        theta = math.pi * latitude / latitude_segments
        ring_radius = math.sin(theta)
        y = -radius_y * math.cos(theta)
        for longitude in range(longitude_segments):
            phi = 2 * math.pi * longitude / longitude_segments
            points.append((radius_x * ring_radius * math.cos(phi), y, radius_z * ring_radius * math.sin(phi)))
    top_index = len(points)
    points.append((0.0, radius_y, 0.0))

    faces: list[tuple[int, int, int]] = []
    first_ring = 1
    for longitude in range(longitude_segments):
        next_longitude = (longitude + 1) % longitude_segments
        faces.append((0, first_ring + next_longitude, first_ring + longitude))

    ring_count = latitude_segments - 1
    for ring in range(ring_count - 1):
        current = 1 + ring * longitude_segments
        following = current + longitude_segments
        for longitude in range(longitude_segments):
            next_longitude = (longitude + 1) % longitude_segments
            faces.append((current + longitude, current + next_longitude, following + next_longitude))
            faces.append((current + longitude, following + next_longitude, following + longitude))

    final_ring = 1 + (ring_count - 1) * longitude_segments
    for longitude in range(longitude_segments):
        next_longitude = (longitude + 1) % longitude_segments
        faces.append((final_ring + longitude, final_ring + next_longitude, top_index))

    return translated(Mesh(tuple(points), tuple(faces)), center)


def torus(
    major_radius: float,
    minor_radius: float,
    *,
    major_segments: int = 14,
    minor_segments: int = 6,
    axis: str = "y",
    center: Vec3 = (0.0, 0.0, 0.0),
) -> Mesh:
    """A compact tubular ring; baseline axis is y (ring in the x/z plane)."""

    points: list[Vec3] = []
    for major_index in range(major_segments):
        major_angle = 2 * math.pi * major_index / major_segments
        for minor_index in range(minor_segments):
            minor_angle = 2 * math.pi * minor_index / minor_segments
            radial = major_radius + minor_radius * math.cos(minor_angle)
            points.append((radial * math.cos(major_angle), minor_radius * math.sin(minor_angle), radial * math.sin(major_angle)))
    faces: list[tuple[int, int, int]] = []
    for major_index in range(major_segments):
        next_major = (major_index + 1) % major_segments
        for minor_index in range(minor_segments):
            next_minor = (minor_index + 1) % minor_segments
            lower_left = major_index * minor_segments + minor_index
            lower_right = major_index * minor_segments + next_minor
            upper_left = next_major * minor_segments + minor_index
            upper_right = next_major * minor_segments + next_minor
            faces.append((lower_left, upper_left, upper_right))
            faces.append((lower_left, upper_right, lower_right))
    return translated(rotate_axis(Mesh(tuple(points), tuple(faces)), axis), center)


def boat_hull() -> Mesh:
    """A shallow faceted scull shell with tapered bow and stern."""

    stations = (
        (-1.55, 0.025, 0.015),
        (-1.20, 0.17, 0.090),
        (-0.45, 0.255, 0.120),
        (0.55, 0.250, 0.120),
        (1.25, 0.145, 0.080),
        (1.55, 0.025, 0.015),
    )
    points: list[Vec3] = []
    for z, half_width, top in stations:
        points.extend((
            (-half_width, -0.12, z),
            (half_width, -0.12, z),
            (half_width, top, z),
            (-half_width, top, z),
        ))
    faces: list[tuple[int, int, int]] = []
    for station in range(len(stations) - 1):
        current = station * 4
        following = (station + 1) * 4
        for corner in range(4):
            next_corner = (corner + 1) % 4
            faces.append((current + corner, following + corner, following + next_corner))
            faces.append((current + corner, following + next_corner, current + next_corner))
    # Cap the narrow bow and stern, preserving visible geometry even at a low camera angle.
    faces.extend(((0, 2, 1), (0, 3, 2)))
    end = (len(stations) - 1) * 4
    faces.extend(((end, end + 1, end + 2), (end, end + 2, end + 3)))
    return Mesh(tuple(points), tuple(faces))


def conifer(height: float, radius: float, center: Vec3) -> Mesh:
    """Stacked tapered cones, recognisable without billboards or textures."""

    trunk = tapered_cylinder(height * 0.28, radius * 0.14, radius * 0.11, segments=8, center=(center[0], center[1] + height * 0.14, center[2]))
    crown_lower = tapered_cylinder(height * 0.56, radius, 0.03, segments=8, center=(center[0], center[1] + height * 0.47, center[2]))
    crown_upper = tapered_cylinder(height * 0.42, radius * 0.72, 0.02, segments=8, center=(center[0], center[1] + height * 0.74, center[2]))
    return merge_meshes((trunk, crown_lower, crown_upper))


def merge_meshes(meshes: Iterable[Mesh]) -> Mesh:
    points: list[Vec3] = []
    faces: list[tuple[int, int, int]] = []
    for mesh in meshes:
        offset = len(points)
        points.extend(mesh.points)
        faces.extend(tuple(index + offset for index in face) for face in mesh.faces)
    return Mesh(tuple(points), tuple(faces))


def components(*entries: tuple[str, Mesh, str]) -> tuple[Component, ...]:
    return tuple(Component(name, mesh, material) for name, mesh, material in entries)


def rower_equipment_nodes() -> dict[str, tuple[Component, ...]]:
    return {
        "visual-hull": components(
            ("shell", boat_hull(), "accent"),
            ("cockpit", box(0.220, 0.045, 0.62, center=(0.0, 0.125, -0.10)), "rubber"),
            ("gunwale-port", tapered_cylinder(2.75, 0.018, 0.012, segments=8, axis="z", center=(-0.245, 0.115, 0.0)), "metal"),
            ("gunwale-starboard", tapered_cylinder(2.75, 0.018, 0.012, segments=8, axis="z", center=(0.245, 0.115, 0.0)), "metal"),
        ),
        "visual-deck-stripe": components(
            ("stripe", box(0.135, 0.018, 2.35), "accent"),
            ("centerline", box(0.020, 0.023, 2.44), "metal"),
        ),
        "visual-footplate": components(
            ("plate", box(0.48, 0.055, 0.13), "metal"),
            ("strap-left", box(0.125, 0.026, 0.085, center=(-0.105, 0.032, 0.0)), "rubber"),
            ("strap-right", box(0.125, 0.026, 0.085, center=(0.105, 0.032, 0.0)), "rubber"),
        ),
        "visual-rail": components(
            ("rail-left", box(0.055, 0.045, 2.78, center=(-0.105, 0.0, 0.0)), "metal"),
            ("rail-right", box(0.055, 0.045, 2.78, center=(0.105, 0.0, 0.0)), "metal"),
        ),
        "visual-seat": components(
            ("seat-cushion", ellipsoid(0.135, 0.040, 0.112, longitude_segments=10, latitude_segments=6, center=(0.0, 0.018, 0.0)), "rubber"),
            ("seat-rail", box(0.185, 0.022, 0.105, center=(0.0, -0.030, 0.0)), "metal"),
        ),
        # The native handle parent supplies its ninety-degree base orientation;
        # therefore this local geometry intentionally remains y-axis aligned.
        "visual-handle": components(
            ("handlebar", tapered_cylinder(0.51, 0.018, 0.018, segments=10, center=(0.0, 0.0, 0.0)), "metal"),
            ("grip-left", tapered_cylinder(0.130, 0.026, 0.026, segments=10, center=(0.0, 0.180, 0.0)), "rubber"),
            ("grip-right", tapered_cylinder(0.130, 0.026, 0.026, segments=10, center=(0.0, -0.180, 0.0)), "rubber"),
        ),
        "visual-oar-port": oar_components(-1.0),
        "visual-oar-starboard": oar_components(1.0),
    }


def oar_components(side: float) -> tuple[Component, ...]:
    return components(
        ("shaft", tapered_cylinder(2.42, 0.018, 0.013, segments=10, axis="x", center=(side * 1.20, 0.0, 0.0)), "metal"),
        ("collar", torus(0.050, 0.010, major_segments=10, minor_segments=4, axis="x"), "rubber"),
        ("blade", box(0.50, 0.032, 0.265, center=(side * 2.42, -0.040, 0.0)), "accent"),
    )


def skierg_equipment_nodes() -> dict[str, tuple[Component, ...]]:
    return {
        "visual-post-L": post_components(),
        "visual-post-R": post_components(),
        "visual-topBar": components(
            ("bar", box(0.72, 0.070, 0.080), "metal"),
            ("display", box(0.200, 0.060, 0.024, center=(0.0, -0.010, 0.053)), "rubber"),
        ),
        "visual-platform": components(
            ("platform", box(0.82, 0.062, 0.62), "accent"),
            ("grip-mat", box(0.560, 0.018, 0.385, center=(0.0, 0.040, 0.015)), "rubber"),
        ),
        "visual-handle-L": handle_components(),
        "visual-handle-R": handle_components(),
        "visual-pole-L": pole_components(),
        "visual-pole-R": pole_components(),
        "visual-cable": components(
            ("cable", tapered_cylinder(1.20, 0.010, 0.010, segments=8), "metal"),
            ("pulley", torus(0.055, 0.009, major_segments=10, minor_segments=4, axis="x", center=(0.0, 0.595, 0.0)), "rubber"),
        ),
    }


def post_components() -> tuple[Component, ...]:
    return components(
        ("post", box(0.086, 1.80, 0.086), "metal"),
        ("trim", box(0.094, 0.100, 0.094, center=(0.0, 0.56, 0.0)), "accent"),
        ("foot", box(0.180, 0.045, 0.210, center=(0.0, -0.900, 0.0)), "rubber"),
    )


def handle_components() -> tuple[Component, ...]:
    return components(
        ("grip", ellipsoid(0.040, 0.045, 0.135, longitude_segments=10, latitude_segments=6), "rubber"),
        ("guard", torus(0.040, 0.008, major_segments=10, minor_segments=4, axis="z", center=(0.0, 0.0, -0.105)), "accent"),
    )


def pole_components() -> tuple[Component, ...]:
    return components(
        ("shaft", tapered_cylinder(1.20, 0.014, 0.010, segments=9, center=(0.0, -0.600, 0.0)), "metal"),
        ("grip", box(0.064, 0.055, 0.170, center=(0.0, 0.0, 0.0)), "rubber"),
        ("basket", torus(0.060, 0.009, major_segments=10, minor_segments=4, center=(0.0, -1.150, 0.0)), "accent"),
    )


def bike_equipment_nodes() -> dict[str, tuple[Component, ...]]:
    return {
        "visual-wheel-front": wheel_components(),
        "visual-wheel-rear": wheel_components(),
        "visual-downTube": components(
            ("tube", tapered_cylinder(1.60, 0.049, 0.040, segments=10, axis="z"), "accent"),
            ("highlight", box(0.025, 0.030, 1.35, center=(0.0, 0.050, 0.0)), "metal"),
        ),
        "visual-seatTube": components(
            ("tube", tapered_cylinder(0.72, 0.050, 0.042, segments=10), "accent"),
            ("collar", torus(0.053, 0.009, major_segments=10, minor_segments=4, center=(0.0, 0.32, 0.0)), "metal"),
        ),
        "visual-topTube": components(
            ("tube", tapered_cylinder(1.12, 0.040, 0.040, segments=10, axis="z"), "accent"),
            ("cable", tapered_cylinder(1.14, 0.007, 0.007, segments=7, axis="z", center=(0.060, 0.048, 0.0)), "metal"),
        ),
        "visual-cranks": components(
            ("arm-left", tapered_cylinder(0.390, 0.018, 0.014, segments=8, center=(0.0, 0.195, 0.0)), "metal"),
            ("arm-right", tapered_cylinder(0.390, 0.018, 0.014, segments=8, center=(0.0, -0.195, 0.0)), "metal"),
            ("hub", torus(0.050, 0.015, major_segments=10, minor_segments=4, axis="y"), "rubber"),
        ),
        "visual-chainRing": components(
            ("ring", torus(0.160, 0.020, major_segments=16, minor_segments=6, axis="y"), "metal"),
            ("spider", tapered_cylinder(0.255, 0.012, 0.012, segments=8, axis="x"), "metal"),
            ("spider-cross", tapered_cylinder(0.255, 0.012, 0.012, segments=8, axis="z"), "metal"),
        ),
        "visual-pedal-L": pedal_components(),
        "visual-pedal-R": pedal_components(),
        "visual-handlebar": components(
            ("bar", tapered_cylinder(0.65, 0.024, 0.024, segments=10, axis="x"), "metal"),
            ("grip-left", tapered_cylinder(0.200, 0.030, 0.030, segments=10, axis="x", center=(-0.290, -0.020, 0.040)), "rubber"),
            ("grip-right", tapered_cylinder(0.200, 0.030, 0.030, segments=10, axis="x", center=(0.290, -0.020, 0.040)), "rubber"),
        ),
        "visual-saddle": components(
            ("saddle", ellipsoid(0.115, 0.038, 0.175, longitude_segments=12, latitude_segments=6), "rubber"),
            ("rail", box(0.115, 0.018, 0.130, center=(0.0, -0.035, -0.010)), "metal"),
        ),
    }


def wheel_components() -> tuple[Component, ...]:
    spokes: list[tuple[str, Mesh, str]] = [
        ("tyre", torus(0.445, 0.030, major_segments=18, minor_segments=7, axis="x"), "rubber"),
        ("rim", torus(0.405, 0.011, major_segments=18, minor_segments=5, axis="x"), "metal"),
        ("hub", ellipsoid(0.045, 0.045, 0.045, longitude_segments=10, latitude_segments=5), "metal"),
    ]
    for index, angle in enumerate((0.0, math.pi / 3, 2 * math.pi / 3)):
        # Bake the three visible spoke directions in the wheel's y/z plane.
        length = 0.79
        thickness = 0.012
        spoke = box(thickness, length, thickness)
        cosine, sine = math.cos(angle), math.sin(angle)
        rotated_points = tuple((point[0], point[1] * cosine - point[2] * sine, point[1] * sine + point[2] * cosine) for point in spoke.points)
        spokes.append((f"spoke-{index}", Mesh(rotated_points, spoke.faces), "accent"))
    return components(*spokes)


def pedal_components() -> tuple[Component, ...]:
    return components(
        ("body", box(0.225, 0.052, 0.105), "rubber"),
        ("reflector", box(0.120, 0.012, 0.030, center=(0.0, 0.033, 0.0)), "accent"),
    )


def rower_environment_nodes() -> dict[str, tuple[Component, ...]]:
    return {
        "environment-ground": components(
            ("water-course", box(120.0, 0.080, 120.0, center=(0.0, -0.060, 0.0)), "water"),
            ("shore-left", box(18.0, 0.45, 120.0, center=(-58.0, 0.12, 0.0)), "shore"),
            ("shore-right", box(18.0, 0.45, 120.0, center=(58.0, 0.12, 0.0)), "shore"),
        ),
        "environment-props": components(
            ("dock", box(2.4, 0.16, 8.0, center=(-18.0, 0.05, -10.0)), "shore"),
            ("dock-rail", tapered_cylinder(7.8, 0.025, 0.025, segments=8, axis="z", center=(-16.9, 0.42, -10.0)), "metal"),
            ("buoy-a", ellipsoid(0.18, 0.12, 0.18, longitude_segments=10, latitude_segments=5, center=(-3.2, 0.08, -8.0)), "accent"),
            ("buoy-b", ellipsoid(0.18, 0.12, 0.18, longitude_segments=10, latitude_segments=5, center=(3.2, 0.08, 8.0)), "accent"),
            ("tree-bank-a", conifer(4.8, 1.45, (-42.0, 0.0, -20.0)), "foliage"),
            ("tree-bank-b", conifer(6.4, 1.80, (43.0, 0.0, 24.0)), "foliage"),
        ),
    }


def skierg_environment_nodes() -> dict[str, tuple[Component, ...]]:
    return {
        "environment-ground": components(
            ("snow-field", box(120.0, 0.10, 120.0, center=(0.0, -0.070, 0.0)), "snow"),
            ("ice-track", box(7.0, 0.035, 86.0, center=(0.0, 0.005, 0.0)), "ice"),
            ("snowbank-left", box(12.0, 1.20, 90.0, center=(-12.0, 0.48, 0.0)), "snow"),
            ("snowbank-right", box(12.0, 1.20, 90.0, center=(12.0, 0.48, 0.0)), "snow"),
        ),
        "environment-props": components(
            ("gate-left", tapered_cylinder(2.1, 0.035, 0.026, segments=8, center=(-3.2, 1.05, -14.0)), "accent"),
            ("gate-right", tapered_cylinder(2.1, 0.035, 0.026, segments=8, center=(3.2, 1.05, -14.0)), "accent"),
            ("gate-bar", box(6.6, 0.07, 0.07, center=(0.0, 1.75, -14.0)), "accent"),
            ("conifer-left", conifer(7.0, 1.9, (-18.0, 0.0, 12.0)), "foliage"),
            ("conifer-right", conifer(5.8, 1.55, (18.0, 0.0, -6.0)), "foliage"),
            ("course-sign", box(2.6, 1.25, 0.10, center=(8.0, 1.10, 18.0)), "metal"),
        ),
    }


def bike_environment_nodes() -> dict[str, tuple[Component, ...]]:
    return {
        "environment-ground": components(
            ("velodrome", box(120.0, 0.11, 120.0, center=(0.0, -0.075, 0.0)), "asphalt"),
            ("track-infield", box(35.0, 0.050, 55.0, center=(0.0, 0.010, 0.0)), "concrete"),
            ("lane-stripe-a", box(0.16, 0.018, 78.0, center=(-3.0, 0.025, 0.0)), "accent"),
            ("lane-stripe-b", box(0.16, 0.018, 78.0, center=(3.0, 0.025, 0.0)), "accent"),
        ),
        "environment-props": components(
            ("barrier-left", box(0.16, 1.0, 32.0, center=(-10.0, 0.50, 0.0)), "metal"),
            ("barrier-right", box(0.16, 1.0, 32.0, center=(10.0, 0.50, 0.0)), "metal"),
            ("banner-left", box(0.06, 1.80, 4.0, center=(-9.85, 1.50, -7.0)), "accent"),
            ("banner-right", box(0.06, 1.80, 4.0, center=(9.85, 1.50, 9.0)), "accent"),
            ("infield-tree", conifer(5.4, 1.50, (-20.0, 0.0, 16.0)), "foliage"),
            ("track-marker", box(4.0, 0.15, 0.50, center=(0.0, 0.10, -30.0)), "concrete"),
        ),
    }


def make_rig_plan(sport: str) -> AssetPlan:
    equipment_by_sport: dict[str, Callable[[], dict[str, tuple[Component, ...]]]] = {
        "rower": rower_equipment_nodes,
        "skierg": skierg_equipment_nodes,
        "bike": bike_equipment_nodes,
    }
    nodes = equipment_by_sport[sport]()
    required_nodes = SPORT_RIG_NODES[sport]
    return AssetPlan(
        filename=f"{sport}-rig.usda",
        sport=sport,
        kind="rig",
        root_name="rig-root",
        required_nodes=required_nodes,
        node_components=tuple((name, nodes[name]) for name in required_nodes),
        materials=RIG_MATERIALS,
        triangle_ceiling=RIG_TRIANGLE_CEILING,
    )


def make_environment_plan(sport: str) -> AssetPlan:
    environment_by_sport: dict[str, Callable[[], dict[str, tuple[Component, ...]]]] = {
        "rower": rower_environment_nodes,
        "skierg": skierg_environment_nodes,
        "bike": bike_environment_nodes,
    }
    nodes = environment_by_sport[sport]()
    # The root is required and intentionally has no geometry; its named child
    # groups carry the independently cloneable ground and prop meshes.
    nodes["environment-root"] = ()
    return AssetPlan(
        filename=f"{sport}-environment.usda",
        sport=sport,
        kind="environment",
        root_name="environment-root",
        required_nodes=ENVIRONMENT_NODES,
        node_components=tuple((name, nodes[name]) for name in ENVIRONMENT_NODES),
        materials=ENVIRONMENT_MATERIALS[sport],
        triangle_ceiling=ENVIRONMENT_TRIANGLE_CEILING,
    )


def plans() -> tuple[AssetPlan, ...]:
    # File ordering is part of deterministic generation and the golden contract.
    return tuple(
        plan
        for sport in ("rower", "skierg", "bike")
        for plan in (make_rig_plan(sport), make_environment_plan(sport))
    )


def component_triangles(component: Component) -> int:
    return len(component.mesh.faces)


def plan_triangles(plan: AssetPlan) -> int:
    return sum(component_triangles(component) for _, node in plan.node_components for component in node)


def plan_points(plan: AssetPlan) -> tuple[Vec3, ...]:
    return tuple(point for _, node in plan.node_components for component in node for point in component.mesh.points)


def plan_bounds(plan: AssetPlan) -> tuple[Vec3, Vec3]:
    points = plan_points(plan)
    if not points:
        raise ValueError(f"{plan.filename} has no generated geometry")
    return (
        tuple(min(point[index] for point in points) for index in range(3)),  # type: ignore[return-value]
        tuple(max(point[index] for point in points) for index in range(3)),  # type: ignore[return-value]
    )


def number(value: float) -> str:
    finite(value)
    # Avoid unstable negative zero in both committed assets and golden bounds.
    if abs(value) < 0.0000005:
        value = 0.0
    return f"{value:.6f}"


def vector(value: Vec3) -> str:
    return f"({number(value[0])}, {number(value[1])}, {number(value[2])})"


def usd_prim_name(logical_name: str) -> str:
    """Return the valid USD identifier for a hyphenated runtime contract name.

    The native logical contract deliberately uses readable names such as
    ``visual-upperArm-L``. USD prim identifiers cannot contain hyphens, so the
    generated prim records that original name in ``rowplay:logicalName`` and
    uses this deterministic underscore form on disk.
    """

    sanitized = logical_name.replace("-", "_")
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", sanitized):
        raise ValueError(f"cannot derive a valid USD prim name from {logical_name!r}")
    return sanitized


def array_lines(type_and_name: str, values: Sequence[str], indent: str, per_line: int = 1) -> list[str]:
    if not values:
        return [f"{indent}{type_and_name} = []"]
    lines = [f"{indent}{type_and_name} = ["]
    for start in range(0, len(values), per_line):
        chunk = ", ".join(values[start:start + per_line])
        if start + per_line < len(values):
            chunk += ","
        lines.append(f"{indent}    {chunk}")
    lines.append(f"{indent}]")
    return lines


def mesh_normals(mesh: Mesh) -> tuple[Vec3, ...]:
    accumulated = [[0.0, 0.0, 0.0] for _ in mesh.points]
    for first, second, third in mesh.faces:
        a, b, c = mesh.points[first], mesh.points[second], mesh.points[third]
        ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        cross = (
            ab[1] * ac[2] - ab[2] * ac[1],
            ab[2] * ac[0] - ab[0] * ac[2],
            ab[0] * ac[1] - ab[1] * ac[0],
        )
        for index in (first, second, third):
            accumulated[index][0] += cross[0]
            accumulated[index][1] += cross[1]
            accumulated[index][2] += cross[2]
    normals: list[Vec3] = []
    for normal in accumulated:
        length = math.sqrt(sum(component * component for component in normal))
        if length < 1e-12:
            normals.append((0.0, 1.0, 0.0))
        else:
            normals.append(tuple(finite(component / length) for component in normal))  # type: ignore[arg-type]
    return tuple(normals)


def render_materials(root_name: str, material_names: Sequence[str], indent: str) -> list[str]:
    lines = [f'{indent}def Scope "materials"', f"{indent}{{"]
    for material_name in material_names:
        color, metallic, roughness = MATERIAL_VALUES[material_name]
        material_indent = indent + "    "
        shader_indent = material_indent + "    "
        lines.extend((
            f'{material_indent}def Material "{material_name}"',
            f"{material_indent}{{",
            f'{shader_indent}token outputs:surface.connect = </{root_name}/materials/{material_name}/preview.outputs:surface>',
            f'{shader_indent}def Shader "preview"',
            f"{shader_indent}{{",
            f'{shader_indent}    uniform token info:id = "UsdPreviewSurface"',
            f"{shader_indent}    color3f inputs:diffuseColor = {vector(color)}",
            f"{shader_indent}    float inputs:metallic = {number(metallic)}",
            f"{shader_indent}    float inputs:roughness = {number(roughness)}",
            f'{shader_indent}    token outputs:surface',
            f"{shader_indent}}}",
            f"{material_indent}}}",
        ))
    lines.append(f"{indent}}}")
    return lines


def render_mesh(component: Component, root_name: str, indent: str) -> list[str]:
    mesh = component.mesh
    normals = mesh_normals(mesh)
    if not mesh.points or not mesh.faces:
        raise ValueError(f"component {component.name} does not contain mesh geometry")
    if len(mesh.points) != len(normals):
        raise ValueError(f"component {component.name} has invalid normals")
    mesh_prim_name = usd_prim_name(f"material_{component.material}_{component.name}")
    lines = [
        # Material-role prefixes are preserved by RealityKit as child entity
        # names. The bundled provider uses `material_accent_` to recolour only
        # authored accent slots on a live or rival clone without guessing from
        # colour values or mutating unrelated kit/metal/skin materials.
        f'{indent}def Mesh "{mesh_prim_name}" (',
        f'{indent}    prepend apiSchemas = ["MaterialBindingAPI"]',
        f"{indent})",
        f"{indent}{{",
        f'{indent}    uniform token subdivisionScheme = "none"',
        f"{indent}    uniform bool doubleSided = true",
    ]
    lines.extend(array_lines("int[] faceVertexCounts", ["3"] * len(mesh.faces), indent + "    ", per_line=16))
    lines.extend(array_lines("int[] faceVertexIndices", [str(index) for face in mesh.faces for index in face], indent + "    ", per_line=12))
    lines.extend(array_lines("normal3f[] normals", [vector(normal) for normal in normals], indent + "    ", per_line=3))
    lines.append(f'{indent}    uniform token normals:interpolation = "vertex"')
    lines.extend(array_lines("point3f[] points", [vector(point) for point in mesh.points], indent + "    ", per_line=3))
    lines.append(f"{indent}    rel material:binding = </{root_name}/materials/{component.material}>")
    lines.append(f"{indent}}}")
    return lines


def render_node(node_name: str, node_components: Sequence[Component], root_name: str, indent: str) -> list[str]:
    lines = [
        f'{indent}def Xform "{usd_prim_name(node_name)}"',
        f"{indent}{{",
        f'{indent}    custom string rowplay:logicalName = "{node_name}"',
    ]
    for component in node_components:
        lines.extend(render_mesh(component, root_name, indent + "    "))
    lines.append(f"{indent}}}")
    return lines


def render_asset(plan: AssetPlan) -> str:
    triangles = plan_triangles(plan)
    if triangles > plan.triangle_ceiling:
        raise ValueError(f"{plan.filename} exceeds its triangle budget before rendering")
    lower_bound, upper_bound = plan_bounds(plan)
    root_prim_name = usd_prim_name(plan.root_name)
    lines = [
        "#usda 1.0",
        "# Generated by script/generate_replay_assets.py; do not edit by hand.",
        f"# rowplay-fixed-seed: {FIXED_SEED}",
        f"# rowplay-triangles: {triangles}",
        "# rowplay-bounds: " + ", ".join(number(value) for value in (*lower_bound, *upper_bound)),
        "# rowplay-material-categories: " + ", ".join(plan.materials),
        "(",
        f'    defaultPrim = "{root_prim_name}"',
        "    metersPerUnit = 1",
        '    upAxis = "Y"',
        ")",
        "",
        f'def Xform "{root_prim_name}"',
        "{",
        f'    custom string rowplay:logicalName = "{plan.root_name}"',
    ]
    lines.extend(render_materials(root_prim_name, plan.materials, "    "))
    for node_name, node_components in plan.node_components:
        if plan.kind == "environment" and node_name == "environment-root":
            # The root is already the outer default primitive. The named nested
            # marker preserves the contract only through the outer prim itself.
            continue
        lines.extend(render_node(node_name, node_components, root_prim_name, "    "))
    lines.append("}")
    return "\n".join(lines) + "\n"


def serialised_bounds(plan: AssetPlan) -> dict[str, list[float]]:
    lower_bound, upper_bound = plan_bounds(plan)
    return {
        "min": [float(number(value)) for value in lower_bound],
        "max": [float(number(value)) for value in upper_bound],
    }


def expected_contract(asset_plans: Sequence[AssetPlan]) -> dict[str, object]:
    resources = []
    for plan in asset_plans:
        resources.append({
            "name": plan.filename,
            "sport": plan.sport,
            "kind": plan.kind,
            "requiredNodes": list(plan.required_nodes),
            "usdPrimNames": {name: usd_prim_name(name) for name in plan.required_nodes},
            "triangleCeiling": plan.triangle_ceiling,
            "expectedBounds": serialised_bounds(plan),
            "requiredMaterialCategories": list(plan.materials),
        })
    return {
        "schemaVersion": CONTRACT_SCHEMA_VERSION,
        "generator": {
            "path": "script/generate_replay_assets.py",
            "command": "python3 script/generate_replay_assets.py",
            "checkCommand": "python3 script/generate_replay_assets.py --check",
            "fixedSeed": FIXED_SEED,
            "standardLibraryOnly": True,
            "networkAccess": "none",
        },
        "budgets": {
            "rigTriangleCeiling": RIG_TRIANGLE_CEILING,
            "environmentTriangleCeiling": ENVIRONMENT_TRIANGLE_CEILING,
            "combinedByteLimitExclusive": COMBINED_BYTE_LIMIT_EXCLUSIVE,
        },
        "resources": resources,
        "environmentContract": {
            "requiredNodes": list(ENVIRONMENT_NODES),
            "noEmbeddedCamerasOrLights": True,
            "directions": {
                "rower": ["water course", "shoreline depth", "buoys", "dock", "restrained vegetation"],
                "skierg": ["snow course", "conifers", "gates", "snowbank depth"],
                "bike": ["paved velodrome-style course", "barriers", "banners", "trackside depth"],
            },
        },
    }


def json_text(value: object) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=True) + "\n"


def provenance_text() -> str:
    return """# Replay 3D Asset Provenance

## Native equipment and environments

The six Phase 11 equipment and environment USDA assets in this directory are
original, project-generated work. They contain no third-party model, texture,
logo, trademark, download, or network-derived source material. Geometry is
generated deterministically from the standard-library-only script in this
repository. These files intentionally contain **no human anatomy**.

Regenerate the committed USDA resources and golden contract with:

```sh
python3 script/generate_replay_assets.py
```

Verify that committed output and the contract have not drifted with:

```sh
python3 script/generate_replay_assets.py --check
```

The fixed generation seed is `20260721`. The assets intentionally contain no
camera or light prims: the native RealityKit scene remains authoritative for
camera, lighting, course placement, effects, and fallback behaviour.

## Canonical V4 athlete (upstream, provisional)

The production athlete is not authored by RowPlay Studio. It is the canonical
RowPlay V4 athlete owned by upstream PR #171 and synchronised by
`script/sync_rowplay_athlete.py` into:

- `rowplay-athlete-v4.usdz`
- `rowplay-athlete-v4.contract.json`
- `rowplay-athlete-v4-source.json`

Low quality and total package failure continue to use the lightweight
procedural athlete. Premium anatomy and most interpenetration work are Phase 12.
"""


def expected_outputs(asset_plans: Sequence[AssetPlan]) -> dict[Path, str]:
    outputs = {RESOURCE_DIRECTORY / plan.filename: render_asset(plan) for plan in asset_plans}
    outputs[CONTRACT_PATH] = json_text(expected_contract(asset_plans))
    outputs[PROVENANCE_PATH] = provenance_text()
    return outputs


def check_asset_text(plan: AssetPlan, text: str) -> list[str]:
    errors: list[str] = []
    triangles = plan_triangles(plan)
    header = re.search(r"^# rowplay-triangles: (\d+)$", text, re.MULTILINE)
    if header is None or int(header.group(1)) != triangles:
        errors.append(f"{plan.filename}: triangle header does not match generated geometry")
    if triangles > plan.triangle_ceiling:
        errors.append(f"{plan.filename}: triangle ceiling exceeded")
    if not text.startswith("#usda 1.0\n"):
        errors.append(f"{plan.filename}: missing USDA header")
    if "def Mesh" not in text:
        errors.append(f"{plan.filename}: missing mesh geometry")
    if re.search(r'\bdef\s+(?:Camera|DistantLight|DomeLight|SphereLight)\b', text):
        errors.append(f"{plan.filename}: embedded camera or light is forbidden")
    if re.search(r"(?i)(?:\bnan\b|\binfinity\b|\b-inf\b)", text):
        errors.append(f"{plan.filename}: non-finite token present")
    for node in plan.required_nodes:
        usd_name = usd_prim_name(node)
        prim_count = len(re.findall(rf'def Xform "{re.escape(usd_name)}"', text))
        logical_count = len(re.findall(
            rf'custom string rowplay:logicalName = "{re.escape(node)}"', text
        ))
        # The outer environment root is also a logical node and must occur
        # exactly once just like every pivotable visual node.
        if prim_count != 1 or logical_count != 1:
            errors.append(
                f"{plan.filename}: required node {node!r} has "
                f"{prim_count} USD prims and {logical_count} logical-name metadata entries"
            )
    for material in plan.materials:
        if f'def Material "{material}"' not in text:
            errors.append(f"{plan.filename}: missing material category {material!r}")
    return errors


def check_contract(contract: dict[str, object], asset_plans: Sequence[AssetPlan]) -> list[str]:
    errors: list[str] = []
    if contract.get("schemaVersion") != CONTRACT_SCHEMA_VERSION:
        errors.append("asset contract schema version differs from generator")
    resources = contract.get("resources")
    if not isinstance(resources, list) or len(resources) != len(asset_plans):
        errors.append("asset contract does not record all six resources")
        return errors
    by_name = {entry.get("name"): entry for entry in resources if isinstance(entry, dict)}
    for plan in asset_plans:
        entry = by_name.get(plan.filename)
        if entry is None:
            errors.append(f"asset contract is missing {plan.filename}")
            continue
        if entry.get("requiredNodes") != list(plan.required_nodes):
            errors.append(f"asset contract node contract drifted for {plan.filename}")
        if entry.get("usdPrimNames") != {name: usd_prim_name(name) for name in plan.required_nodes}:
            errors.append(f"asset contract USD name mapping drifted for {plan.filename}")
        if entry.get("triangleCeiling") != plan.triangle_ceiling:
            errors.append(f"asset contract triangle ceiling drifted for {plan.filename}")
        if entry.get("expectedBounds") != serialised_bounds(plan):
            errors.append(f"asset contract bounds drifted for {plan.filename}")
        if entry.get("requiredMaterialCategories") != list(plan.materials):
            errors.append(f"asset contract material contract drifted for {plan.filename}")
    return errors


def validate_outputs(asset_plans: Sequence[AssetPlan], expected: dict[Path, str]) -> list[str]:
    errors: list[str] = []
    actual_asset_texts: dict[Path, str] = {}
    for plan in asset_plans:
        path = RESOURCE_DIRECTORY / plan.filename
        try:
            actual = path.read_text(encoding="utf-8")
        except OSError:
            errors.append(f"missing generated asset: {path.relative_to(REPOSITORY_ROOT)}")
            continue
        actual_asset_texts[path] = actual
        if actual != expected[path]:
            errors.append(f"asset differs from deterministic generator: {path.relative_to(REPOSITORY_ROOT)}")
        errors.extend(check_asset_text(plan, actual))

    total_bytes = sum(len(text.encode("utf-8")) for text in actual_asset_texts.values())
    if total_bytes >= COMBINED_BYTE_LIMIT_EXCLUSIVE:
        errors.append(f"all six assets are {total_bytes} bytes, outside the {COMBINED_BYTE_LIMIT_EXCLUSIVE}-byte limit")

    try:
        contract_text = CONTRACT_PATH.read_text(encoding="utf-8")
        contract = json.loads(contract_text)
    except (OSError, json.JSONDecodeError) as error:
        errors.append(f"cannot load asset contract: {error}")
    else:
        if contract_text != expected[CONTRACT_PATH]:
            errors.append("asset contract differs from deterministic generator")
        if isinstance(contract, dict):
            errors.extend(check_contract(contract, asset_plans))
        else:
            errors.append("asset contract root must be an object")

    try:
        provenance = PROVENANCE_PATH.read_text(encoding="utf-8")
    except OSError:
        errors.append("asset provenance file is missing")
    else:
        if provenance != expected[PROVENANCE_PATH]:
            errors.append("asset provenance differs from deterministic generator")
    return errors


def write_outputs(outputs: dict[Path, str]) -> None:
    for path, text in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify committed output without writing files")
    arguments = parser.parse_args(argv)

    asset_plans = plans()
    expected = expected_outputs(asset_plans)
    if arguments.check:
        errors = validate_outputs(asset_plans, expected)
        if errors:
            for error in errors:
                print(f"error: {error}", file=sys.stderr)
            return 1
        print("Replay 3D assets and contract are deterministic and valid.")
        return 0

    write_outputs(expected)
    print(f"Generated {len(asset_plans)} replay USDA assets, provenance, and golden contract (seed {FIXED_SEED}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
