#!/usr/bin/env node

/**
 * Export a deterministic V4 motion-graph corpus from an exact RowPlay Git
 * tree. This deliberately reads `git show <commit>:...` rather than the
 * checkout, so a developer's local RowPlay branch or uncommitted files cannot
 * alter a native parity fixture.
 *
 * Usage:
 *   node --experimental-strip-types script/export_rowplay_motion_parity.mjs \
 *     --rowplay-repo ../rowplay \
 *     --commit da0dc73bf295871e9b362511cd5b2c9a9424b325 \
 *     --output Tests/RowPlayCoreTests/Fixtures/replay-motion-graph-v4.json
 */

import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const FINAL_COMMIT = "da0dc73bf295871e9b362511cd5b2c9a9424b325";
const SAMPLE_COUNT = 129;

function argument(name, fallback) {
  const index = process.argv.indexOf(name);
  if (index === -1) return fallback;
  const value = process.argv[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`Missing value for ${name}`);
  return value;
}

function git(repository, args) {
  return execFileSync("git", ["-C", repository, ...args], { encoding: "utf8" });
}

function poseFor(sport, phaseIndex) {
  const cycle = phaseIndex / SAMPLE_COUNT;
  const phase = cycle * Math.PI * 2;
  const strokeSeconds = sport === "bike" ? 0.75 : sport === "skierg" ? 1.875 : 60 / 28;
  const driveFrac = sport === "bike" ? 0.5 : sport === "skierg" ? 0.34 : 0.38;
  const intensity = ((phaseIndex * 37) % SAMPLE_COUNT) / (SAMPLE_COUNT - 1);
  return {
    index: 7,
    phase,
    warpedPhase: phase,
    cycleFrac: cycle,
    driveFrac,
    drive: cycle < driveFrac,
    driveProgress: cycle < driveFrac ? cycle / driveFrac : 1,
    recoveryProgress: cycle < driveFrac ? 0 : (cycle - driveFrac) / (1 - driveFrac),
    strokeSeconds,
    strokeMeters: sport === "bike" ? 5 : sport === "skierg" ? 8 : 11,
    rate: 60 / strokeSeconds,
    watts: 200,
    intensity,
    amplitude: 1,
    fatigue: 0,
    real: true,
  };
}

const repository = resolve(argument("--rowplay-repo", "../rowplay"));
const commit = argument("--commit", FINAL_COMMIT);
const output = resolve(argument(
  "--output",
  "Tests/RowPlayCoreTests/Fixtures/replay-motion-graph-v4.json",
));

git(repository, ["cat-file", "-e", `${commit}^{commit}`]);
git(repository, ["merge-base", "--is-ancestor", commit, "origin/main"]);
const sourcePath = "src/lib/replay/motionGraph.ts";
const source = git(repository, ["show", `${commit}:${sourcePath}`]);
const temporaryDirectory = mkdtempSync(join(tmpdir(), "rowplay-motion-parity-"));
const modulePath = join(temporaryDirectory, basename(sourcePath));

try {
  writeFileSync(modulePath, source, "utf8");
  const motion = await import(`${pathToFileURL(modulePath).href}?commit=${commit}`);
  const samples = [];
  for (const sport of ["rower", "skierg", "bike"]) {
    for (let phaseIndex = 0; phaseIndex < SAMPLE_COUNT; phaseIndex += 1) {
      const pose = poseFor(sport, phaseIndex);
      samples.push({
        sport,
        phaseIndex,
        pose,
        graph: motion.sampleMotionGraph(sport, pose),
      });
    }
  }
  writeFileSync(
    output,
    `${JSON.stringify({
      schema: "rowplay.replay.motion-parity.v4",
      upstreamCommit: commit,
      sourcePath,
      sampleCountPerSport: SAMPLE_COUNT,
      samples,
    }, null, 2)}\n`,
    "utf8",
  );
} finally {
  rmSync(temporaryDirectory, { recursive: true, force: true });
}
