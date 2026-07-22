#!/usr/bin/env python3
"""Synchronise the merged RowPlay V4 athlete into RowPlay Studio.

The Studio bundle deliberately consumes immutable blobs from one exact merged
RowPlay Git tree.  It never consults the checkout's working tree or HEAD, so a
developer can keep a different RowPlay branch checked out while safely
refreshing or checking the native package.

Run from the Studio repository root:

    python3 script/sync_rowplay_athlete.py \
      --rowplay-repo /path/to/rowplay \
      --expected-commit da0dc73bf295871e9b362511cd5b2c9a9424b325

    python3 script/sync_rowplay_athlete.py \
      --rowplay-repo /path/to/rowplay \
      --expected-commit da0dc73bf295871e9b362511cd5b2c9a9424b325 \
      --check
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
RESOURCE_DIRECTORY = (
    REPOSITORY_ROOT / "Sources" / "RowPlayStudio" / "Resources" / "Replay3D"
)

# This is the merge commit of RowPlay PR #171, not a convenient local checkout
# revision.  Keep all expected upstream facts in this one synchroniser; the
# bundled source manifest is the runtime authority used by Swift.
DEFAULT_EXPECTED_COMMIT = "da0dc73bf295871e9b362511cd5b2c9a9424b325"
DEFAULT_UPSTREAM_PR = 171
DEFAULT_UPSTREAM_REPOSITORY = "https://github.com/shenghaoc/rowplay"
DEFAULT_STATUS = "merged"

EXPECTED_GLB_SHA256 = "73e0ece3e6c6de5a7a020a5097b172ca3e0ed8315c27ff604159b144fa90547b"
EXPECTED_USDZ_SHA256 = "934b0d3af0454f60a84dde76f95b77121919f5ad7cfc366684a670ae5d99658e"
EXPECTED_CONTRACT_SHA256 = (
    "e9fb56f372ac1ea44ee5ccaf1d00b5a975e1eb4a1a2ee7843ab9e53609fb189d"
)

USDZ_FILENAME = "rowplay-athlete-v4.usdz"
CONTRACT_FILENAME = "rowplay-athlete-v4.contract.json"
GLB_FILENAME = "rowplay-athlete-v4.glb"
SOURCE_MANIFEST_FILENAME = "rowplay-athlete-v4-source.json"
ASSET_DIRECTORY = "static/replay-assets"

BUNDLED_USDZ = RESOURCE_DIRECTORY / USDZ_FILENAME
BUNDLED_CONTRACT = RESOURCE_DIRECTORY / CONTRACT_FILENAME
BUNDLED_SOURCE = RESOURCE_DIRECTORY / SOURCE_MANIFEST_FILENAME


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_bytes(repo: Path, *arguments: str) -> bytes:
    result = subprocess.run(
        ["git", "-C", str(repo), *arguments],
        check=False,
        capture_output=True,
    )
    if result.returncode:
        message = result.stderr.decode("utf-8", errors="replace").strip()
        raise SystemExit(message or f"git {' '.join(arguments)} failed")
    return result.stdout


def git_text(repo: Path, *arguments: str) -> str:
    return git_bytes(repo, *arguments).decode("utf-8", errors="strict").strip()


def git_blob(repo: Path, commit: str, path: str) -> bytes:
    object_name = f"{commit}:{path}"
    # `show` reads the tree object directly, independent of the worktree.
    return git_bytes(repo, "show", object_name)


def load_json(data: bytes) -> dict[str, Any]:
    parsed = json.loads(data.decode("utf-8"))
    if not isinstance(parsed, dict):
        raise SystemExit("expected JSON object")
    return parsed


def dump_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def verify_upstream(
    rowplay_repo: Path,
    expected_commit: str,
) -> tuple[bytes, bytes, bytes, dict[str, Any]]:
    if not rowplay_repo.is_dir():
        raise SystemExit(f"rowplay repo does not exist: {rowplay_repo}")

    # A revision may exist only in an unrelated local branch.  Require the
    # canonical merge to be a commit reachable from the local origin/main ref.
    git_text(rowplay_repo, "cat-file", "-e", f"{expected_commit}^{{commit}}")
    reachable = subprocess.run(
        [
            "git", "-C", str(rowplay_repo), "merge-base", "--is-ancestor",
            expected_commit, "origin/main",
        ],
        check=False,
        capture_output=True,
    )
    if reachable.returncode != 0:
        raise SystemExit(
            f"pinned commit {expected_commit} is not reachable from rowplay/origin/main"
        )

    glb = git_blob(rowplay_repo, expected_commit, f"{ASSET_DIRECTORY}/{GLB_FILENAME}")
    usdz = git_blob(rowplay_repo, expected_commit, f"{ASSET_DIRECTORY}/{USDZ_FILENAME}")
    contract_bytes = git_blob(
        rowplay_repo, expected_commit, f"{ASSET_DIRECTORY}/{CONTRACT_FILENAME}"
    )

    actual_glb = sha256_bytes(glb)
    actual_usdz = sha256_bytes(usdz)
    actual_contract = sha256_bytes(contract_bytes)
    if actual_glb != EXPECTED_GLB_SHA256:
        raise SystemExit(f"GLB hash mismatch: got {actual_glb}, expected {EXPECTED_GLB_SHA256}")
    if actual_usdz != EXPECTED_USDZ_SHA256:
        raise SystemExit(f"USDZ hash mismatch: got {actual_usdz}, expected {EXPECTED_USDZ_SHA256}")
    if actual_contract != EXPECTED_CONTRACT_SHA256:
        raise SystemExit(
            f"contract hash mismatch: got {actual_contract}, expected {EXPECTED_CONTRACT_SHA256}"
        )

    contract = load_json(contract_bytes)
    if contract.get("schema") != "rowplay.replay.athlete.v4":
        raise SystemExit(f"unexpected contract schema: {contract.get('schema')!r}")
    if contract.get("schemaVersion") != 1:
        raise SystemExit(
            f"unexpected contract schemaVersion: {contract.get('schemaVersion')!r}"
        )
    clips = ((contract.get("animation") or {}).get("clips") or [])
    expected_clips = {
        ("rower", "rowplay-v4-row-cycle"),
        ("skierg", "rowplay-v4-ski-cycle"),
        ("bike", "rowplay-v4-bike-cycle"),
    }
    actual_clips = {
        (clip.get("sport"), clip.get("name"))
        for clip in clips
        if isinstance(clip, dict)
    }
    if actual_clips != expected_clips:
        raise SystemExit(f"canonical clip contract drifted: {sorted(actual_clips)!r}")

    web = contract.get("webRuntimeArtifact") or {}
    native = contract.get("nativeDerivativeArtifact") or {}
    if web.get("sha256") != EXPECTED_GLB_SHA256:
        raise SystemExit("contract webRuntimeArtifact.sha256 drifted from pin")
    if native.get("sha256") != EXPECTED_USDZ_SHA256:
        raise SystemExit("contract nativeDerivativeArtifact.sha256 drifted from pin")

    return usdz, contract_bytes, glb, contract


def build_source_manifest(
    *,
    expected_commit: str,
    contract: dict[str, Any],
    sync_command: str,
) -> dict[str, Any]:
    return {
        "athleteAuthorship": (
            "RowPlay Studio does not author the athlete. The V4 athlete, "
            "skeleton, animations, and movement landmarks are owned by the "
            "merged upstream rowplay repository."
        ),
        "contractSchema": contract.get("schema"),
        "contractSchemaVersion": contract.get("schemaVersion"),
        "contractSha256": EXPECTED_CONTRACT_SHA256,
        "copiedUsdzSha256": EXPECTED_USDZ_SHA256,
        "glbSha256": EXPECTED_GLB_SHA256,
        "pinnedCommit": expected_commit,
        "provenance": {
            "forbiddenSources": (contract.get("provenance") or {}).get(
                "forbiddenSources", []
            ),
            "licence": (contract.get("provenance") or {}).get("licence"),
            "owner": (contract.get("provenance") or {}).get("owner"),
            "source": (contract.get("provenance") or {}).get("source"),
        },
        "status": DEFAULT_STATUS,
        "syncCommand": sync_command,
        "upstreamPR": DEFAULT_UPSTREAM_PR,
        "upstreamRepository": DEFAULT_UPSTREAM_REPOSITORY,
        "usdzSha256": EXPECTED_USDZ_SHA256,
    }


def manifests_match(expected: dict[str, Any], actual: dict[str, Any]) -> list[str]:
    keys = (
        "pinnedCommit",
        "glbSha256",
        "usdzSha256",
        "contractSha256",
        "copiedUsdzSha256",
        "status",
        "upstreamPR",
        "upstreamRepository",
        "contractSchema",
        "contractSchemaVersion",
        "athleteAuthorship",
        "provenance",
        "syncCommand",
    )
    return [key for key in keys if actual.get(key) != expected.get(key)]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Synchronise the merged RowPlay V4 athlete into Studio resources."
    )
    parser.add_argument(
        "--rowplay-repo",
        type=Path,
        required=True,
        help="Path to a local checkout of the rowplay repository",
    )
    parser.add_argument(
        "--expected-commit",
        default=DEFAULT_EXPECTED_COMMIT,
        help="Exact merged RowPlay commit whose tree is consumed",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify bundled resources match the immutable Git-tree pin without writing",
    )
    args = parser.parse_args(argv)

    usdz, contract_bytes, _glb, contract = verify_upstream(
        args.rowplay_repo.resolve(),
        args.expected_commit,
    )
    # Keep the bundled provenance deterministic and free of a developer's
    # workstation path. The actual repository argument is only an input to the
    # local synchronisation command, never product metadata.
    sync_command = (
        "python3 script/sync_rowplay_athlete.py "
        "--rowplay-repo /path/to/rowplay "
        f"--expected-commit {args.expected_commit}"
    )
    manifest = build_source_manifest(
        expected_commit=args.expected_commit,
        contract=contract,
        sync_command=sync_command,
    )

    if args.check:
        failures: list[str] = []
        if not BUNDLED_USDZ.is_file() or sha256_file(BUNDLED_USDZ) != EXPECTED_USDZ_SHA256:
            failures.append("bundled USDZ is missing or stale")
        if not BUNDLED_CONTRACT.is_file() or sha256_file(BUNDLED_CONTRACT) != EXPECTED_CONTRACT_SHA256:
            failures.append("bundled contract is missing or stale")
        if not BUNDLED_SOURCE.is_file():
            failures.append("source manifest is missing")
        else:
            drifted = manifests_match(manifest, load_json(BUNDLED_SOURCE.read_bytes()))
            failures.extend(f"source manifest field drifted: {key}" for key in drifted)
        if failures:
            for failure in failures:
                print(f"error: {failure}", file=sys.stderr)
            return 1
        print(f"ok: bundled V4 athlete matches merged pin {args.expected_commit[:12]}")
        return 0

    RESOURCE_DIRECTORY.mkdir(parents=True, exist_ok=True)
    BUNDLED_USDZ.write_bytes(usdz)
    BUNDLED_CONTRACT.write_bytes(contract_bytes)
    dump_json(BUNDLED_SOURCE, manifest)

    if sha256_file(BUNDLED_USDZ) != EXPECTED_USDZ_SHA256:
        raise SystemExit("copied USDZ hash verification failed")
    if sha256_file(BUNDLED_CONTRACT) != EXPECTED_CONTRACT_SHA256:
        raise SystemExit("copied contract hash verification failed")

    print(f"synced {USDZ_FILENAME} ({EXPECTED_USDZ_SHA256[:12]}…)")
    print(f"synced {CONTRACT_FILENAME} ({EXPECTED_CONTRACT_SHA256[:12]}…)")
    print(f"wrote {SOURCE_MANIFEST_FILENAME} pin={args.expected_commit}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
