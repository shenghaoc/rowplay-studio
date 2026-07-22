#!/usr/bin/env python3
"""Synchronise the provisional RowPlay V4 athlete into RowPlay Studio.

The canonical athlete is authored in the rowplay repository (PR #171). This
script copies a pinned provisional snapshot into the Studio resource bundle.
It performs no network access and never regenerates geometry.

Run from the repository root:

    python3 script/sync_rowplay_athlete.py \\
      --rowplay-repo /path/to/rowplay \\
      --expected-commit dba7211bfa94d3f86e60b75921bd5853ec736f55

    python3 script/sync_rowplay_athlete.py \\
      --rowplay-repo /path/to/rowplay \\
      --expected-commit dba7211bfa94d3f86e60b75921bd5853ec736f55 \\
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

# Mechanical pin: update these constants together when refreshing PR #171.
DEFAULT_EXPECTED_COMMIT = "dba7211bfa94d3f86e60b75921bd5853ec736f55"
DEFAULT_UPSTREAM_PR = 171
DEFAULT_UPSTREAM_REPOSITORY = "https://github.com/shenghaoc/rowplay"
DEFAULT_STATUS = "provisional"

EXPECTED_GLB_SHA256 = "a9a215f07bd39d15daa5c45c5bfbbb1788656ad7916fc39f172c5dcc78129963"
EXPECTED_USDZ_SHA256 = "5591b13c7d58bc4f44194728c1a2fc1c669086232d2f1bd97723672392c50723"
EXPECTED_CONTRACT_SHA256 = (
    "96acec971c3247120e71af726388420dd89866437c76c3a417ea267481976dba"
)

USDZ_FILENAME = "rowplay-athlete-v4.usdz"
CONTRACT_FILENAME = "rowplay-athlete-v4.contract.json"
GLB_FILENAME = "rowplay-athlete-v4.glb"
SOURCE_MANIFEST_FILENAME = "rowplay-athlete-v4-source.json"

BUNDLED_USDZ = RESOURCE_DIRECTORY / USDZ_FILENAME
BUNDLED_CONTRACT = RESOURCE_DIRECTORY / CONTRACT_FILENAME
BUNDLED_SOURCE = RESOURCE_DIRECTORY / SOURCE_MANIFEST_FILENAME


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_rev_parse(repo: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def verify_upstream(
    rowplay_repo: Path,
    expected_commit: str,
) -> tuple[Path, Path, Path, dict[str, Any]]:
    if not rowplay_repo.is_dir():
        raise SystemExit(f"rowplay repo does not exist: {rowplay_repo}")

    head = git_rev_parse(rowplay_repo)
    if head != expected_commit:
        raise SystemExit(
            f"upstream HEAD {head} does not match expected commit {expected_commit}"
        )

    asset_dir = rowplay_repo / "static" / "replay-assets"
    glb_path = asset_dir / GLB_FILENAME
    usdz_path = asset_dir / USDZ_FILENAME
    contract_path = asset_dir / CONTRACT_FILENAME

    for path in (glb_path, usdz_path, contract_path):
        if not path.is_file():
            raise SystemExit(f"missing upstream artifact: {path}")

    glb_hash = sha256_file(glb_path)
    usdz_hash = sha256_file(usdz_path)
    contract_hash = sha256_file(contract_path)

    if glb_hash != EXPECTED_GLB_SHA256:
        raise SystemExit(
            f"GLB hash mismatch: got {glb_hash}, expected {EXPECTED_GLB_SHA256}"
        )
    if usdz_hash != EXPECTED_USDZ_SHA256:
        raise SystemExit(
            f"USDZ hash mismatch: got {usdz_hash}, expected {EXPECTED_USDZ_SHA256}"
        )
    if contract_hash != EXPECTED_CONTRACT_SHA256:
        raise SystemExit(
            f"contract hash mismatch: got {contract_hash}, expected {EXPECTED_CONTRACT_SHA256}"
        )

    contract = load_json(contract_path)
    if contract.get("schema") != "rowplay.replay.athlete.v4":
        raise SystemExit(f"unexpected contract schema: {contract.get('schema')!r}")

    web = contract.get("webRuntimeArtifact") or {}
    native = contract.get("nativeDerivativeArtifact") or {}
    if web.get("sha256") != EXPECTED_GLB_SHA256:
        raise SystemExit("contract webRuntimeArtifact.sha256 drifted from pin")
    if native.get("sha256") != EXPECTED_USDZ_SHA256:
        raise SystemExit("contract nativeDerivativeArtifact.sha256 drifted from pin")

    return usdz_path, contract_path, glb_path, contract


def build_source_manifest(
    *,
    expected_commit: str,
    contract: dict[str, Any],
    usdz_hash: str,
    sync_command: str,
) -> dict[str, Any]:
    return {
        "athleteAuthorship": (
            "RowPlay Studio does not author the athlete. The V4 athlete, "
            "skeleton, animations, and movement landmarks are owned by the "
            "upstream rowplay repository."
        ),
        "contractSchema": contract.get("schema"),
        "contractSchemaVersion": contract.get("schemaVersion"),
        "contractSha256": EXPECTED_CONTRACT_SHA256,
        "copiedUsdzSha256": usdz_hash,
        "expectedCommit": expected_commit,
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


def files_match(source: Path, destination: Path) -> bool:
    if not destination.is_file():
        return False
    return sha256_file(source) == sha256_file(destination)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Synchronise the pinned RowPlay V4 athlete into Studio resources."
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
        help="Exact provisional/final commit that must be checked out",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify bundled resources match the pin without writing",
    )
    args = parser.parse_args(argv)

    usdz_path, contract_path, _glb_path, contract = verify_upstream(
        args.rowplay_repo.resolve(),
        args.expected_commit,
    )
    usdz_hash = sha256_file(usdz_path)
    sync_command = (
        "python3 script/sync_rowplay_athlete.py "
        f"--rowplay-repo {args.rowplay_repo} "
        f"--expected-commit {args.expected_commit}"
    )
    manifest = build_source_manifest(
        expected_commit=args.expected_commit,
        contract=contract,
        usdz_hash=usdz_hash,
        sync_command=sync_command,
    )

    if args.check:
        failures: list[str] = []
        if not BUNDLED_USDZ.is_file() or sha256_file(BUNDLED_USDZ) != EXPECTED_USDZ_SHA256:
            failures.append("bundled USDZ is missing or stale")
        if (
            not BUNDLED_CONTRACT.is_file()
            or sha256_file(BUNDLED_CONTRACT) != EXPECTED_CONTRACT_SHA256
        ):
            failures.append("bundled contract is missing or stale")
        if not BUNDLED_SOURCE.is_file():
            failures.append("source manifest is missing")
        else:
            bundled_manifest = load_json(BUNDLED_SOURCE)
            for key in (
                "pinnedCommit",
                "glbSha256",
                "usdzSha256",
                "contractSha256",
                "copiedUsdzSha256",
                "status",
                "upstreamPR",
            ):
                if bundled_manifest.get(key) != manifest.get(key):
                    failures.append(f"source manifest field drifted: {key}")
        if failures:
            for failure in failures:
                print(f"error: {failure}", file=sys.stderr)
            return 1
        print(
            "ok: bundled V4 athlete matches provisional pin "
            f"{args.expected_commit[:12]}"
        )
        return 0

    RESOURCE_DIRECTORY.mkdir(parents=True, exist_ok=True)
    BUNDLED_USDZ.write_bytes(usdz_path.read_bytes())
    BUNDLED_CONTRACT.write_text(contract_path.read_text(encoding="utf-8"), encoding="utf-8")
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
