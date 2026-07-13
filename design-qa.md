# Design QA: Split Focus Workout Detail

- Source visual truth: `/Users/shenghaochen/.codex/generated_images/019f58da-330b-7573-90e0-cb6e785353a7/exec-cee2c0cc-2d38-4cdd-b0da-0637c86347a1.png`
- Implementation screenshot: `/private/tmp/rowplay-product-design-qa/implementation-accepted-clean.png`
- Combined comparison: `/private/tmp/rowplay-product-design-qa/comparison-final.png`
- Viewport: native macOS window at approximately 1000 x 768; source mock is 1440 x 1024
- State: light appearance, demo 2000m test selected, workout tools collapsed

## Full-view comparison evidence

The implementation preserves the source hierarchy: native workout sidebar, quiet title block, ruled metric ribbon, stacked pace and power lanes over distance, and a precise split table. At the smaller implementation viewport the table continues below the fold, which is expected responsive behavior rather than hidden content.

## Focused comparison evidence

The full-view comparison was sufficient because the relevant fidelity surfaces are code-native text, Charts marks, SF Symbols, and native controls. There are no raster assets, logos, illustrations, or custom icons requiring a crop-level asset comparison.

## Findings

No actionable P0, P1, or P2 differences remain.

- Typography: SF Pro and monospaced performance numerals match the selected direction. The ribbon uses a responsive 18-point metric size to avoid truncation in narrower windows.
- Spacing and layout: flat ruled sections replace the previous card stack; chart lanes and split table follow one continuous vertical rhythm.
- Colors and tokens: monitor blue, power orange, cadence violet, and heart-rate red retain their documented semantic roles with adaptive light/dark variants.
- Image quality: not applicable; the selected direction contains no raster imagery, and the implementation uses native SF Symbols and Swift Charts.
- Copy and content: labels and values use real workout fields. Available calories and average heart rate appear in the ribbon; unavailable data is not invented.
- Accessibility: every ribbon metric has an explicit label and value. The chart retains the existing grouped chart description, and pace is plotted so faster values rise visually.

## Comparison history

1. Initial pass: the selected mock showed faster pace rising, while the implementation plotted raw pace seconds and made the finishing surge fall. The metric ribbon also omitted available calories and heart rate.
2. Fix: pace values are plotted on an inverted numeric scale with formatted pace labels; calories and average heart rate were added conditionally.
3. Responsive pass: the average pace suffix truncated at the narrower app viewport.
4. Fix: the ribbon now shows the concise pace value while the label supplies its meaning; full `/500m` units remain on the chart and split table.
5. Post-fix evidence: `/private/tmp/rowplay-product-design-qa/comparison-final.png` shows the corrected rising finish, complete metric ribbon, aligned chart lanes, and unclipped primary values.

## Interaction checks

- Sidebar workout selection remains active and exposes the selected workout.
- Sport filter and reload toolbar controls remain present.
- Replay Workout remains available in the toolbar.
- Workout Tools remains a native disclosure control.
- Accessibility tree exposes all metrics, chart summary, split values, and actions.

## Follow-up polish

- P3: add compact split-average annotations directly inside each chart lane when a future chart-label pass can keep them readable across interval workouts with many splits.

final result: passed
