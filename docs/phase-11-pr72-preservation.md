# Phase 11 PR #72 preservation record

This branch is an intentionally unfinished archive of the local Phase 11
continuation. It is not a review branch and must not be merged.

- Preserved on: 2026-08-03
- Original local branch: `codex/phase-11-production-3d-assets`
- Original local base/head before preservation: `19e45386c2cd7fc30ac153455d574ad217387b08`
- Remote PR #72 head: `ae2b1c4dd3c28ebd427e961b17f25b80169b2037`
- Snapshot commit: `e8ca71aa8f38583f02782f568f758132de484569`
- Snapshot size: 118 files, 18,883 insertions, 11,754 deletions
- Reference resource inventory: 53 files, approximately 16 MB
- Largest file: `rowplay-athlete-v4.usdz`, 11,565,117 bytes

The complete changed-file inventory is the tree of the snapshot commit. The
reference manifests record the individual upstream and shipped-file hashes.
Key preserved artifact SHA-256 values are:

| Artifact | SHA-256 |
|---|---|
| `rowplay-athlete-v4.usdz` | `cf65202b8360183be57308130226173171ac67d8d900e02f40ba3879569b569a` |
| `rowplay-motion.bin` | `52cee22a7b8989dc321115b6e300cb3b42cc87ec903b013f7be9e7a22e4607fe` |
| `rowplay-row-equipment.usdz` | `39f5edf0d36167fd4fd63db8ce2c0d113336085ee9f2f6da7ae02b02c5ec7ec5` |
| `rowplay-ski-equipment.usdz` | `331f5c28511e269ce5a6cbb02f6b192436183f2ee1dbed087349417504e4e13e` |
| `rowplay-bike-equipment.usdz` | `d0c6b9355749bb75a2276f8a2007419de994da1471db32de0c46df700754cf0e` |

Pre-commit inspection found no file above GitHub's 100 MB limit. Secret-pattern
matches were confined to deliberate fake-token privacy tests. Asset provenance
is recorded in `ASSET_PROVENANCE.md` and the reference manifests.
