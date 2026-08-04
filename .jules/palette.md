## 2026-07-03 - Accessibility Consolidation for Visual Groupings
**Learning:** SwiftUI accessibility defaults often fail for layout containers holding disparate textual elements (like an icon, metric value, and label) or visual dividers (like bullet dots in a horizontal list). By default, VoiceOver may read these components independently and include decorative visual characters, resulting in a fractured and noisy auditory experience (e.g. reading a middle dot `·` repeatedly).
**Action:** When creating visual tiles or lists of attributes, use `.accessibilityElement(children: .ignore)` alongside explicit `.accessibilityLabel()` and `.accessibilityValue()` to merge the elements into a single logical item. Furthermore, make sure to explicitly hide decorative textual characters (like "·" separators) using `.accessibilityHidden(true)`.

## 2026-07-12 - Slider and Button Accessibility
**Learning:** Bare Sliders in SwiftUI require explicit `.accessibilityLabel` and `.accessibilityValue` to be usable by VoiceOver. Additionally, disabled buttons should use the `.help` modifier to explain *why* they are disabled, providing a better experience for mouse users.
**Action:** When adding interactive elements like Sliders, ensure VoiceOver context is provided. When disabling buttons, add a dynamic `.help` tooltip explaining the required action to enable it.

## 2026-07-15 - Hide decorative text separators from VoiceOver
**Learning:** Screen readers will read out decorative text characters (like bullet points or "·" separators), creating a noisy and poor auditory experience for visually impaired users.
**Action:** When using decorative characters to separate elements visually in a `Text` view, apply a custom `.accessibilityLabel` that uses commas for natural VoiceOver pauses instead of wrapping separators in individual `Text("·").accessibilityHidden(true)` views. The single-`Text` approach keeps the view hierarchy flat and performant while achieving the same visual and auditory result.

## 2026-07-20 - [UX: Disabled Button Explanations]
**Learning:** Hiding UI elements completely when their prerequisites aren't met (e.g. hiding "Replay Workout" when there's no stroke data) causes confusion. Users may think the feature was removed or wonder where it is. Showing the button but disabling it and adding a tooltip/hint explaining *why* it's disabled is far better UX.
**Action:** When a button's required data or state is unavailable, prefer `.disabled(true)` paired with a dynamic `.help()` and `.accessibilityHint()` explaining the reason over conditionally rendering (hiding) the button.

## 2026-07-25 - Provide VoiceOver hints for disabled buttons
**Learning:** Sighted mouse users can read the `.help()` tooltips explaining why an action is unavailable, but without an `.accessibilityHint()`, VoiceOver users only hear "Dimmed", leaving them guessing why they can't perform an action.
**Action:** When a button's required data or state is unavailable, pair `.disabled(true)` with both a dynamic `.help()` tooltip for mouse users and a corresponding `.accessibilityHint()` to provide context to screen reader users.

## 2026-07-27 - Accessibility grouping for heterogeneous layout attributes
**Learning:** Even standard horizontal layouts of distinct textual attributes (like date, time, and tags) can cause fractured screen reading if not explicitly grouped.
**Action:** Apply `.accessibilityElement(children: .ignore)` and construct a unified comma-separated `.accessibilityLabel` to merge independent metadata elements in an HStack into a single, cohesive phrase for VoiceOver.

## 2026-07-31 - Preserve Text flow over HStack separation for Accessibility
**Learning:** In SwiftUI, splitting a single `Text` view into an `HStack` of multiple `Text` views to individually hide decorative characters (like '·') from VoiceOver using `.accessibilityHidden(true)` is an anti-pattern. This breaks SwiftUI's built-in text wrapping, potentially causing truncation or layout issues on narrow screens, and combined `accessibilityElement(children: .combine)` still fails to insert necessary natural reading pauses, creating run-on sentences.
**Action:** Keep visual text layout within a single interpolated `Text` view (which wraps perfectly) and handle the auditory experience by providing an explicit `.accessibilityLabel` where the decorative separators are replaced with semantic punctuation like commas for natural VoiceOver pauses.

## 2026-08-03 - Selection States on Custom Button Controls
**Learning:** In SwiftUI, when building custom selection controls (like interval pickers) using `Button` with tinting for visual selection, VoiceOver users receive no indication of which option is currently active unless explicit traits are provided. Compact visual labels ("30s", "1m") are also poor spoken names.
**Action:** Dynamically apply `.accessibilityAddTraits(.isSelected)` to the active element, pair it with a full spoken `.accessibilityLabel` (and matching `.help` tooltip), and mark the section title with `.isHeader` so the control group is navigable.

## 2026-08-04 - Explicit Accessibility Hints for Icon-Only Pickers and Menus
**Learning:** Icon-only pickers and menus often have an `.accessibilityLabel` and `.help` tooltip, but VoiceOver users may still not know the control opens a menu or what can be chosen. A concise `.accessibilityHint` fills that gap. Self-explanatory action labels (e.g. "Play replay", "Remove rival") usually do not need a hint that only restates the label.
**Action:** For icon-only menus/pickers whose label does not imply "opens a menu to choose…", add an `.accessibilityHint` that describes the result (e.g. "Opens a menu to select the camera angle"). Do not add hints that merely paraphrase a clear action label. For ternary help/hint strings, wrap each arm in `LocalizedStringKey(...)`.
