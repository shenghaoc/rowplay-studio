## 2024-07-30 - Avoid HStack for text separators
**Learning:** Splitting a single logical sentence into an HStack to hide decorative characters like '·' from VoiceOver breaks visual text wrapping and creates run-on sentences.
**Action:** Use a single concatenated Text view and apply an explicit .accessibilityLabel or .accessibilityValue where separators are replaced with commas for natural pauses.
