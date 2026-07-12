# Computer Use Automation Readiness — Requirements

## R1. Full production accessibility traversal

Computer Use must return a nonempty semantic tree for the normal staged
RowPlayStudio.app. It must not crash or disconnect `SkyComputerUseService`.
The tree must expose the main window, sidebar, selected workout detail or
dashboard, toolbar controls, and Replay Workout action.

## R2. Controlled isolation of the bad element

Identify the exact RowPlay view or accessibility payload that triggers
`AccessibilitySupport.UIElementError` (EXC_BREAKPOINT/SIGTRAP in
SkyComputerUseService). Use progressive isolation rather than speculative
edits. Record the reproduction and confirmed root cause in design.md.

## R3. Preserve accessibility

The fix must preserve meaningful VoiceOver names, values, roles, grouping,
selection state, and actions. Do not hide entire charts, lists, workout rows,
or controls merely to make Computer Use pass. If a framework-generated
accessibility representation is incompatible, provide an explicit semantic
representation or summary with equivalent user information.

## R4. Deterministic automation launch

Add an optional documented launch mode: `./script/build_and_run.sh
--automation`. It may select deterministic demo data, suppress
nondeterministic background sync, and disable nonessential animation. The
ordinary production launch must also remain inspectable. Automation mode must
not bypass production navigation or replace the app with a test-only screen.

## R5. Bundle and discovery consistency

Keep technical identity stable:

- app directory = `RowPlayStudio.app`
- executable = `RowPlayStudio`
- CFBundleName = `RowPlayStudio`
- bundle identifier = `com.shenghaoc.RowPlayStudio`

Keep the human-facing name in `CFBundleDisplayName = RowPlay Studio`.
Generate Info.plist before final bundle signing. Ad-hoc sign the completed
staged bundle with a stable identifier if required. Validate the bundle with
`codesign --verify --deep --strict`. Computer Use must work when targeting the
absolute app path.

## R6. Diagnostics

Add concise launch/automation telemetry sufficient to confirm staged-app
identity, launch, automation mode, and main-content presentation. Combined
with the Computer Use result and helper crash reports, this evidence must
distinguish app-side launch/window failures from external accessibility-helper
failures. The app must not claim to observe helper-process crashes directly.
Do not log workout contents, Concept2 tokens, file paths containing user data,
or other sensitive data.

## R7. Tests and documentation

Add focused tests for any new launch configuration, accessibility-summary
helper, or deterministic automation state. Update roadmap, beta-readiness,
source-map, and the Kiro task checklist to match the shipped implementation
and actual manual proof.
