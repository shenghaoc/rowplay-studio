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
