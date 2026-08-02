#!/usr/bin/env node

/**
 * Export the full native-parity corpus from an exact RowPlay Git tree.
 *
 * Supersedes `export_rowplay_motion_parity.mjs`: one deterministic run reads
 * every source with `git show <commit>:...` (never the checkout, so a local
 * RowPlay branch or uncommitted files cannot alter a fixture), evaluates the
 * exact modules under Node's TypeScript type stripping, and writes:
 *
 *   Tests/RowPlayCoreTests/Fixtures/replay-motion-graph-v4.json      (legacy schema)
 *   Tests/RowPlayCoreTests/Fixtures/replay-current-main-motion.json  (motion graph)
 *   Tests/RowPlayCoreTests/Fixtures/replay-current-main-grips.json   (hand-grip closure)
 *   Tests/RowPlayCoreTests/Fixtures/replay-current-main-equipment.json
 *   Tests/RowPlayCoreTests/Fixtures/replay-current-main-2d.json      (2D kinematics + palettes)
 *
 * Usage:
 *   node script/export_rowplay_native_parity.mjs \
 *     --rowplay-repo ../rowplay \
 *     --commit 4d96480e7c6fb382f800555bd3aa463d9fe5b1a6
 *
 * Requires Node >= 23.6 (built-in type stripping) and the RowPlay checkout's
 * node_modules (three.js is a runtime dependency of handGrip.ts/rigV4.ts).
 */

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const PINNED_COMMIT = "4d96480e7c6fb382f800555bd3aa463d9fe5b1a6";
const GENERATOR_VERSION = "export_rowplay_native_parity/1.0.0";
const MOTION_SAMPLE_COUNT = 129;
const KINEMATICS_SAMPLE_COUNT = 64;
const SKI_ELBOW_SAMPLE_COUNT = 32;
const OAR_YAW_SAMPLE_COUNT = 20;
const ELBOW_FLEXION_SAMPLE_COUNT = 10;
const BIKE_KNEE_SAMPLE_COUNT = 16;
const SADDLE_GRID_XS = 11;
const SADDLE_GRID_ZS = 15;

function argument(name, fallback) {
  const index = process.argv.indexOf(name);
  if (index === -1) return fallback;
  const value = process.argv[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`Missing value for ${name}`);
  return value;
}

function git(repository, args) {
  return execFileSync("git", ["-C", repository, ...args], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
}

function sha256(text) {
  return createHash("sha256").update(text, "utf8").digest("hex");
}

/**
 * Node's type stripping erases types but performs no module resolution, so
 * TypeScript-style extensionless relative imports must gain their `.ts`
 * extension before evaluation. Only import/export specifiers are rewritten;
 * recorded SHA-256 hashes are always of the original extracted bytes.
 */
function withResolvedImports(source) {
  return source.replace(
    /(from\s+")(\.{1,2}\/[^"]+)(")/g,
    (match, prefix, specifier, suffix) =>
      /\.(ts|js|mjs|cjs|json)$/.test(specifier)
        ? match
        : `${prefix}${specifier}.ts${suffix}`,
  );
}

/** Deterministic pose scheme shared with the original motion parity export. */
function poseFor(sport, phaseIndex, sampleCount) {
  const cycle = phaseIndex / sampleCount;
  const phase = cycle * Math.PI * 2;
  const strokeSeconds = sport === "bike" ? 0.75 : sport === "skierg" ? 1.875 : 60 / 28;
  const driveFrac = sport === "bike" ? 0.5 : sport === "skierg" ? 0.34 : 0.38;
  const intensity = ((phaseIndex * 37) % sampleCount) / (sampleCount - 1);
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

/** Extract one exported object literal (e.g. `export const VENUES_LIGHT ... = {…}`). */
function extractObjectLiteral(source, marker) {
  const markerIndex = source.indexOf(marker);
  if (markerIndex === -1) throw new Error(`Marker not found: ${marker}`);
  const equalsIndex = source.indexOf("=", markerIndex);
  const start = source.indexOf("{", equalsIndex);
  let depth = 0;
  let inString = null;
  let inLineComment = false;
  let inBlockComment = false;
  for (let index = start; index < source.length; index += 1) {
    const character = source[index];
    const next = source[index + 1];
    if (inLineComment) {
      if (character === "\n") inLineComment = false;
      continue;
    }
    if (inBlockComment) {
      if (character === "*" && next === "/") {
        inBlockComment = false;
        index += 1;
      }
      continue;
    }
    if (inString) {
      if (character === "\\") index += 1;
      else if (character === inString) inString = null;
      continue;
    }
    if (character === '"' || character === "'" || character === "`") {
      inString = character;
      continue;
    }
    if (character === "/" && next === "/") {
      inLineComment = true;
      continue;
    }
    if (character === "/" && next === "*") {
      inBlockComment = true;
      continue;
    }
    if (character === "{") depth += 1;
    if (character === "}") {
      depth -= 1;
      if (depth === 0) {
        const literal = source.slice(start, index + 1);
        return new Function(`"use strict"; return (${literal});`)();
      }
    }
  }
  throw new Error(`Unbalanced object literal for ${marker}`);
}

const vec3 = (vector) => [vector.x, vector.y, vector.z];
const quat = (quaternion) => [quaternion.x, quaternion.y, quaternion.z, quaternion.w];

/**
 * Flatten a sampled graph into sorted dotted-path numeric leaves — exactly the
 * key naming `ReplayMotionGraphParityTests.flatten` uses, so the columnar
 * current-main fixture and the Swift tests agree on channel identifiers.
 */
function flattenNumericLeaves(value, path, output) {
  if (value !== null && typeof value === "object") {
    for (const key of Object.keys(value).sort()) {
      flattenNumericLeaves(value[key], path ? `${path}.${key}` : key, output);
    }
  } else if (typeof value === "number") {
    output.push([path, value]);
  }
  return output;
}

const repository = resolve(argument("--rowplay-repo", "../rowplay"));
const commit = argument("--commit", PINNED_COMMIT);
const fixturesDirectory = resolve(
  argument("--fixtures-dir", "Tests/RowPlayCoreTests/Fixtures"),
);

git(repository, ["cat-file", "-e", `${commit}^{commit}`]);
git(repository, ["merge-base", "--is-ancestor", commit, "origin/main"]);

const SOURCE_PATHS = {
  motionGraph: "src/lib/replay/motionGraph.ts",
  strokeModel: "src/lib/replay/strokeModel.ts",
  sportKinematics: "src/lib/replay/sportKinematics.ts",
  handGrip: "src/lib/replay/handGrip.ts",
  rigV4: "src/lib/replay/rigV4.ts",
  rowRig: "src/lib/replay/rowRig.ts",
  figurePose: "src/lib/replay/figurePose.ts",
  skiEquipment: "src/lib/replay/skiEquipment.ts",
  bikeRig: "src/lib/replay/bikeRig.js",
  bikeSaddle: "src/lib/replay/bikeSaddle.js",
  renderer: "src/lib/replay/renderer.ts",
  athleteContract: "static/replay-assets/rowplay-athlete-v4.contract.json",
};

const sources = {};
const hashes = {};
for (const [key, path] of Object.entries(SOURCE_PATHS)) {
  const text = git(repository, ["show", `${commit}:${path}`]);
  sources[key] = text;
  hashes[path] = sha256(text);
}

function hashesFor(...keys) {
  const output = {};
  for (const key of keys) output[SOURCE_PATHS[key]] = hashes[SOURCE_PATHS[key]];
  return output;
}

const nodeModules = join(repository, "node_modules");
if (!existsSync(join(nodeModules, "three", "package.json"))) {
  throw new Error(
    `three.js not found under ${nodeModules}; run npm/pnpm install in the RowPlay checkout first`,
  );
}

const temporaryDirectory = mkdtempSync(join(tmpdir(), "rowplay-native-parity-"));

try {
  symlinkSync(nodeModules, join(temporaryDirectory, "node_modules"), "dir");
  const evaluated = [
    "motionGraph",
    "sportKinematics",
    "handGrip",
    "rigV4",
    "rowRig",
    "figurePose",
    "skiEquipment",
    "bikeRig",
    "bikeSaddle",
  ];
  for (const key of evaluated) {
    writeFileSync(
      join(temporaryDirectory, basename(SOURCE_PATHS[key])),
      withResolvedImports(sources[key]),
      "utf8",
    );
  }
  writeFileSync(
    join(temporaryDirectory, "three-bridge.mjs"),
    'export * as THREE from "three";\n',
    "utf8",
  );

  const load = async (name) =>
    import(`${pathToFileURL(join(temporaryDirectory, name)).href}?commit=${commit}`);
  const motion = await load("motionGraph.ts");
  const kinematics = await load("sportKinematics.ts");
  const handGrip = await load("handGrip.ts");
  const rowRig = await load("rowRig.ts");
  const skiEquipment = await load("skiEquipment.ts");
  const bikeRig = await load("bikeRig.js");
  const bikeSaddle = await load("bikeSaddle.js");
  const { THREE } = await load("three-bridge.mjs");

  // ── 1. Motion-graph corpus (legacy schema + current-main schema) ─────────
  const motionSamples = [];
  for (const sport of ["rower", "skierg", "bike"]) {
    for (let phaseIndex = 0; phaseIndex < MOTION_SAMPLE_COUNT; phaseIndex += 1) {
      const pose = poseFor(sport, phaseIndex, MOTION_SAMPLE_COUNT);
      motionSamples.push({
        sport,
        phaseIndex,
        pose,
        graph: motion.sampleMotionGraph(sport, pose),
      });
    }
  }
  writeFileSync(
    join(fixturesDirectory, "replay-motion-graph-v4.json"),
    `${JSON.stringify(
      {
        schema: "rowplay.replay.motion-parity.v4",
        upstreamCommit: commit,
        sourcePath: SOURCE_PATHS.motionGraph,
        sampleCountPerSport: MOTION_SAMPLE_COUNT,
        samples: motionSamples,
      },
      null,
      2,
    )}\n`,
    "utf8",
  );
  // Columnar channel layout: dotted channel paths are recorded once per
  // sport, values per sample — same numbers as the legacy fixture at ~40% of
  // the size, with channel names identical to the Swift flatten helpers.
  const channelsBySport = {};
  const columnarSamples = motionSamples.map((sample) => {
    const leaves = flattenNumericLeaves(sample.graph, "", []);
    const channels = leaves.map(([path]) => path);
    const known = channelsBySport[sample.sport];
    if (!known) {
      channelsBySport[sample.sport] = channels;
    } else if (JSON.stringify(known) !== JSON.stringify(channels)) {
      throw new Error(`Channel shape varies across ${sample.sport} samples`);
    }
    return {
      sport: sample.sport,
      phaseIndex: sample.phaseIndex,
      pose: sample.pose,
      values: leaves.map(([, value]) => value),
    };
  });
  writeFileSync(
    join(fixturesDirectory, "replay-current-main-motion.json"),
    `${JSON.stringify({
      schema: "rowplay.replay.current-main.motion-parity.v1",
      sourceCommit: commit,
      generatorVersion: GENERATOR_VERSION,
      sourceFileSha256s: hashesFor("motionGraph", "strokeModel"),
      sampleCountPerSport: MOTION_SAMPLE_COUNT,
      sampleCount: motionSamples.length,
      channelsBySport,
      samples: columnarSamples,
    })}\n`,
    "utf8",
  );

  // ── 2. Hand-grip closure corpus ──────────────────────────────────────────
  const contract = JSON.parse(sources.athleteContract);
  const helperByName = new Map(contract.bones.helpers.map((helper) => [helper.name, helper]));

  function buildHand(side) {
    const handName = side < 0 ? "v4LeftHand" : "v4RightHand";
    const hand = new THREE.Object3D();
    hand.name = handName;
    const nodes = new Map([[handName, hand]]);
    const ensure = (name) => {
      const existing = nodes.get(name);
      if (existing) return existing;
      const helper = helperByName.get(name);
      if (!helper) throw new Error(`Contract is missing helper ${name}`);
      const node = new THREE.Object3D();
      node.name = name;
      node.position.fromArray(helper.restLocalTransform.translation);
      node.quaternion.fromArray(helper.restLocalTransform.rotationQuaternion);
      ensure(helper.parent).add(node);
      nodes.set(name, node);
      return node;
    };
    const prefix = side < 0 ? "v4Left" : "v4Right";
    for (const helper of contract.bones.helpers) {
      if (helper.name.startsWith(prefix)) ensure(helper.name);
    }
    return { hand, getBone: (name) => nodes.get(name) ?? null };
  }

  const jointJSON = (joint) => ({
    helper: joint.helper,
    position: vec3(joint.position),
    quaternion: quat(joint.quaternion),
  });
  const chainJSON = (chain) => ({
    digit: chain.digit,
    tipLength: chain.tipLength,
    cupNode: chain.cupNode ? jointJSON(chain.cupNode) : null,
    joints: chain.joints.map(jointJSON),
  });

  const chainsBySide = {};
  const handsJSON = {};
  for (const side of [-1, 1]) {
    const { hand, getBone } = buildHand(side);
    const chains = handGrip.collectHandDigitChains(hand, getBone, side);
    if (chains.length !== 5) {
      throw new Error(`Expected 5 digit chains for side ${side}, found ${chains.length}`);
    }
    chainsBySide[side] = chains;
    handsJSON[side < 0 ? "left" : "right"] = {
      handBone: hand.name,
      chains: chains.map(chainJSON),
    };
  }

  const sportGripOptions = {
    rower: {
      radius: rowRig.ROWER_SCULL_GRIP.radius,
      thumbEndAxial: rowRig.ROWER_SCULL_GRIP.anchorFromEnd,
      thumbOppose: 0.3,
      wrapFingerStages: false,
    },
    skierg: {
      radius: skiEquipment.SKI_POLE_GRIP_RADIUS,
      thumbEndAxial: null,
      thumbOppose: skiEquipment.SKI_POLE_THUMB_OPPOSE,
      wrapFingerStages: false,
    },
    bike: {
      radius: bikeRig.BIKE_RIG.handlebar.hood.radius,
      thumbEndAxial: null,
      thumbOppose: 1.56,
      wrapFingerStages: true,
    },
  };

  const contactJSON = (contact) => ({
    digit: contact.digit,
    surfaceDistance: contact.surfaceDistance,
    segmentSurfaceDistance:
      contact.segmentSurfaceDistance === undefined ? null : contact.segmentSurfaceDistance,
    contact: contact.contact,
    tip: [contact.tip[0], contact.tip[1], contact.tip[2]],
  });

  const closures = {};
  for (const [sport, options] of Object.entries(sportGripOptions)) {
    const perSide = {};
    for (const side of [-1, 1]) {
      const surface = { radius: options.radius };
      if (options.thumbEndAxial !== null) surface.thumbEndAxial = options.thumbEndAxial;
      const closure = handGrip.solveHandGripClosure(chainsBySide[side], {
        side,
        surface,
        thumbOppose: options.thumbOppose,
        ...(options.wrapFingerStages ? { wrapFingerStages: true } : {}),
      });
      perSide[side < 0 ? "left" : "right"] = {
        poses: closure.poses.map((pose) => ({
          helper: pose.helper,
          flex: pose.flex,
          oppose: pose.oppose,
        })),
        contacts: closure.contacts.map(contactJSON),
      };
    }
    closures[sport] = { options, ...perSide };
  }

  const channelCentres = (side) => {
    const centres = {};
    for (const [sport, options] of Object.entries(sportGripOptions)) {
      centres[sport] = {
        radius: options.radius,
        centre: vec3(handGrip.handChannelCentre(options.radius, side)),
      };
    }
    return centres;
  };
  const channel = {
    handCurlAxis: { ...handGrip.HAND_CURL_AXIS },
    handFistCentre: { ...handGrip.HAND_FIST_CENTRE },
    handFistRadius: handGrip.HAND_FIST_RADIUS,
    handFistReferenceGripRadius: handGrip.HAND_FIST_REFERENCE_GRIP_RADIUS,
    handPalmContact: { ...handGrip.HAND_PALM_CONTACT },
    handPalmNormalIn: { ...handGrip.HAND_PALM_NORMAL_IN },
    handGripSeatFlesh: handGrip.HAND_GRIP_SEAT_FLESH,
    handLongAxis: { ...handGrip.HAND_LONG_AXIS },
    handPalmNormalOut: { ...handGrip.HAND_PALM_NORMAL_OUT },
    handClosureCup: handGrip.HAND_CLOSURE_CUP,
    defaultDigitFlesh:
      handGrip.HAND_FIST_RADIUS - handGrip.HAND_FIST_REFERENCE_GRIP_RADIUS,
    perSide: {
      left: {
        curlAxis: vec3(handGrip.handCurlAxis(-1)),
        curlAxisThumbward: vec3(handGrip.handCurlAxisThumbward(-1)),
        longAxis: vec3(handGrip.handLongAxis(-1)),
        palmNormalOut: vec3(handGrip.handPalmNormalOut(-1)),
        channelCentres: channelCentres(-1),
      },
      right: {
        curlAxis: vec3(handGrip.handCurlAxis(1)),
        curlAxisThumbward: vec3(handGrip.handCurlAxisThumbward(1)),
        longAxis: vec3(handGrip.handLongAxis(1)),
        palmNormalOut: vec3(handGrip.handPalmNormalOut(1)),
        channelCentres: channelCentres(1),
      },
    },
  };

  writeFileSync(
    join(fixturesDirectory, "replay-current-main-grips.json"),
    `${JSON.stringify(
      {
        schema: "rowplay.replay.current-main.grip-parity.v1",
        sourceCommit: commit,
        generatorVersion: GENERATOR_VERSION,
        sourceFileSha256s: hashesFor("handGrip", "rigV4", "athleteContract"),
        sampleCount: Object.keys(sportGripOptions).length * 2,
        channel,
        helpers: contract.bones.helpers.map((helper) => ({
          name: helper.name,
          parent: helper.parent,
          translation: helper.restLocalTransform.translation,
          rotationQuaternion: helper.restLocalTransform.rotationQuaternion,
        })),
        hands: handsJSON,
        closures,
      },
      null,
      2,
    )}\n`,
    "utf8",
  );

  // ── 3. Equipment contract corpus ─────────────────────────────────────────
  const oarYawSamples = [];
  for (let index = 0; index < OAR_YAW_SAMPLE_COUNT; index += 1) {
    const unit = index / (OAR_YAW_SAMPLE_COUNT - 1);
    const side = index % 2 === 0 ? 1 : -1;
    const input = {
      shoulder: [
        side * 0.25,
        1.05 + 0.25 * Math.sin(index * 1.7),
        -0.15 + 0.3 * Math.cos(index * 0.9),
      ],
      pinX: side * rowRig.ROWER_OARLOCK.lateral,
      pinY: rowRig.ROWER_OARLOCK.y,
      pinZ: rowRig.ROWER_OARLOCK.z,
      signedInboard: index === 18 ? 0 : side * 0.78,
      bladeRoll: -0.5 + 0.8 * unit,
      requestedReach: 0.55 + 0.4 * unit,
      preferredYaw: -1.1 + 2.2 * unit,
      forceReachBoundary: index % 3 === 0,
    };
    const output = rowRig.solveRowerOarYaw(
      new THREE.Vector3(...input.shoulder),
      input.pinX,
      input.pinY,
      input.pinZ,
      input.signedInboard,
      input.bladeRoll,
      input.requestedReach,
      input.preferredYaw,
      input.forceReachBoundary,
    );
    oarYawSamples.push({ input, output });
  }

  const armLengths = {
    upperArmLength: skiEquipment.SKI_ATHLETE_PROPORTIONS.upperArmLength,
    forearmLength: skiEquipment.SKI_ATHLETE_PROPORTIONS.forearmLength,
  };
  const flexionChords = [0.01, 0.15, 0.25, 0.38, 0.52, 0.65, 0.78, 0.88, 0.94, 0.97];
  const elbowFlexionSamples = flexionChords.map((chordLength) => ({
    chordLength,
    ...armLengths,
    output: rowRig.rowerElbowFlexion(
      chordLength,
      armLengths.upperArmLength,
      armLengths.forearmLength,
    ),
  }));
  const flexionInputs = [-0.2, 0, 0.32, 0.6, 1.0, 1.5, 2.0, 2.46, 3.0, 3.3];
  const reachForFlexionSamples = flexionInputs.map((flexion) => ({
    flexion,
    ...armLengths,
    output: rowRig.rowerReachForFlexion(
      flexion,
      armLengths.upperArmLength,
      armLengths.forearmLength,
    ),
  }));
  if (
    flexionChords.length !== ELBOW_FLEXION_SAMPLE_COUNT ||
    flexionInputs.length !== ELBOW_FLEXION_SAMPLE_COUNT
  ) {
    throw new Error("Elbow-flexion sample tables drifted from the documented count");
  }

  const bikeKneeSamples = [];
  for (let index = 0; index < BIKE_KNEE_SAMPLE_COUNT; index += 1) {
    const angle = (index * 2 * Math.PI) / BIKE_KNEE_SAMPLE_COUNT;
    bikeKneeSamples.push({ angle, output: bikeRig.bikeKneeFlexion(angle) });
  }

  const saddleXs = [];
  for (let index = 0; index < SADDLE_GRID_XS; index += 1) {
    saddleXs.push(-0.08 + (0.16 * index) / (SADDLE_GRID_XS - 1));
  }
  const saddleZs = [];
  for (let index = 0; index < SADDLE_GRID_ZS; index += 1) {
    saddleZs.push(-0.06 + (0.24 * index) / (SADDLE_GRID_ZS - 1));
  }
  const saddleDrops = saddleZs.map((z) =>
    saddleXs.map((x) => {
      const drop = bikeSaddle.bikeSaddleDropAt(x, z);
      return drop === null ? null : drop;
    }),
  );

  const skierElbowSamples = [];
  for (let index = 0; index < SKI_ELBOW_SAMPLE_COUNT; index += 1) {
    const pose = poseFor("skierg", index, SKI_ELBOW_SAMPLE_COUNT);
    const skier = kinematics.solveSkierKinematics(pose);
    const direction = kinematics.solveSkierElbowDirection(skier);
    skierElbowSamples.push({
      pose,
      kinematics: { ...skier },
      direction: { vertical: direction.vertical, foreAft: direction.foreAft },
    });
  }

  const equipmentSampleCount =
    oarYawSamples.length +
    elbowFlexionSamples.length +
    reachForFlexionSamples.length +
    bikeKneeSamples.length +
    SADDLE_GRID_XS * SADDLE_GRID_ZS +
    skierElbowSamples.length;

  writeFileSync(
    join(fixturesDirectory, "replay-current-main-equipment.json"),
    `${JSON.stringify(
      {
        schema: "rowplay.replay.current-main.equipment-parity.v1",
        sourceCommit: commit,
        generatorVersion: GENERATOR_VERSION,
        sourceFileSha256s: hashesFor(
          "rowRig",
          "figurePose",
          "skiEquipment",
          "handGrip",
          "rigV4",
          "bikeRig",
          "bikeSaddle",
          "sportKinematics",
          "motionGraph",
        ),
        sampleCount: equipmentSampleCount,
        row: {
          footContact: { ...rowRig.ROWER_FOOT_CONTACT },
          stretcher: { ...rowRig.ROWER_STRETCHER },
          scullGrip: { ...rowRig.ROWER_SCULL_GRIP },
          oarlock: { ...rowRig.ROWER_OARLOCK },
          elbowCorridor: { ...rowRig.ROWER_ELBOW_CORRIDOR },
          elbowPlane: {
            authorityStart: rowRig.ROWER_ELBOW_PLANE.authorityStart,
            authorityFull: rowRig.ROWER_ELBOW_PLANE.authorityFull,
            relaxed: { ...rowRig.ROWER_ELBOW_PLANE.relaxed },
            drawn: { ...rowRig.ROWER_ELBOW_PLANE.drawn },
            drawnOutboardWeight: rowRig.ROWER_ELBOW_PLANE.drawnOutboardWeight,
            drawnDownWeight: rowRig.ROWER_ELBOW_PLANE.drawnDownWeight,
          },
          drawFinishFlexion: rowRig.ROWER_DRAW_FINISH_FLEXION,
          drawSoftFlexion: rowRig.ROWER_DRAW_SOFT_FLEXION,
        },
        ski: {
          athleteProportions: { ...skiEquipment.SKI_ATHLETE_PROPORTIONS },
          gripShift: skiEquipment.SKI_GRIP_SHIFT,
          poleGripRadius: skiEquipment.SKI_POLE_GRIP_RADIUS,
          poleThumbOppose: skiEquipment.SKI_POLE_THUMB_OPPOSE,
          equipmentDetail: skiEquipment.SKI_EQUIPMENT_DETAIL,
        },
        bike: {
          rig: bikeRig.BIKE_RIG,
          wheelAxleY: bikeRig.bikeWheelAxleY(),
          saddleTopY: bikeRig.bikeSaddleTopY(),
          riderHipY: bikeRig.bikeRiderHipY(),
        },
        saddle: {
          stations: bikeSaddle.BIKE_SADDLE_STATIONS,
          shellThickness: bikeSaddle.BIKE_SADDLE_SHELL_THICKNESS,
          rearZ: bikeSaddle.BIKE_SADDLE_REAR_Z,
          noseZ: bikeSaddle.BIKE_SADDLE_NOSE_Z,
          length: bikeSaddle.BIKE_SADDLE_LENGTH,
          maxHalfWidth: bikeSaddle.BIKE_SADDLE_MAX_HALF_WIDTH,
        },
        samples: {
          oarYaw: oarYawSamples,
          elbowFlexion: elbowFlexionSamples,
          reachForFlexion: reachForFlexionSamples,
          bikeKneeFlexion: bikeKneeSamples,
          saddleDrop: { xs: saddleXs, zs: saddleZs, drops: saddleDrops },
          skierElbowDirection: skierElbowSamples,
        },
      },
      null,
      2,
    )}\n`,
    "utf8",
  );

  // ── 4. 2D kinematics + venue palettes ────────────────────────────────────
  const kinematicsSamples = [];
  const solvers = {
    rower: kinematics.solveRowerKinematics,
    skierg: kinematics.solveSkierKinematics,
    bike: kinematics.solveBikeKinematics,
  };
  for (const sport of ["rower", "skierg", "bike"]) {
    for (let phaseIndex = 0; phaseIndex < KINEMATICS_SAMPLE_COUNT; phaseIndex += 1) {
      const pose = poseFor(sport, phaseIndex, KINEMATICS_SAMPLE_COUNT);
      kinematicsSamples.push({
        sport,
        phaseIndex,
        pose,
        kinematics: { ...solvers[sport](pose) },
      });
    }
  }

  const colorKeys = ["live", "ghost", "skin", "skinShade", "hair", "shoe", "foam"];
  const pickColors = (palette) =>
    Object.fromEntries(colorKeys.map((key) => [key, palette[key]]));
  const palettes = {
    venuesLight: extractObjectLiteral(sources.renderer, "export const VENUES_LIGHT"),
    venuesDark: extractObjectLiteral(sources.renderer, "export const VENUES_DARK"),
    colorsLight: pickColors(extractObjectLiteral(sources.renderer, "export const COLORS_LIGHT")),
    colorsDark: pickColors(extractObjectLiteral(sources.renderer, "export const COLORS_DARK")),
  };

  writeFileSync(
    join(fixturesDirectory, "replay-current-main-2d.json"),
    `${JSON.stringify({
      schema: "rowplay.replay.current-main.kinematics-parity.v1",
      sourceCommit: commit,
      generatorVersion: GENERATOR_VERSION,
      sourceFileSha256s: hashesFor("sportKinematics", "motionGraph", "renderer"),
      sampleCountPerSport: KINEMATICS_SAMPLE_COUNT,
      sampleCount: kinematicsSamples.length,
      samples: kinematicsSamples,
      palettes,
    })}\n`,
    "utf8",
  );

  console.log(`Exported native parity fixtures at ${commit} into ${fixturesDirectory}`);
} finally {
  rmSync(temporaryDirectory, { recursive: true, force: true });
}
