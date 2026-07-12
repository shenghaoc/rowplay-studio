## 2024-05-18 - Slider and Button Accessibility

**Learning:** Bare Sliders in SwiftUI require explicit `.accessibilityLabel` and `.accessibilityValue` to be usable by VoiceOver. Additionally, disabled buttons should use the `.help` modifier to explain *why* they are disabled, providing a better experience for mouse users.

**Action:** When adding interactive elements like Sliders, ensure VoiceOver context is provided. When disabling buttons, add a dynamic `.help` tooltip explaining the required action to enable it.
