---
name: RowPlay Studio
description: Native macOS Concept2 logbook analytics and workout replay for erg athletes.
colors:
  monitor-blue: "#0066CC"
  monitor-blue-dark: "#0A84FF"
  split-orange: "#9A5700"
  split-orange-dark: "#FF9F0A"
  green-zone-green: "#137333"
  green-zone-green-dark: "#30D158"
  red-zone-red: "#B3261E"
  red-zone-red-dark: "#FF453A"
  cadence-violet: "#7B2CBF"
  cadence-violet-dark: "#BF5AF2"
  caution-amber: "#7A5A00"
  caution-amber-dark: "#FFD60A"
  duration-teal: "#007A99"
  duration-teal-dark: "#64D2FF"
typography:
  hero:
    fontFamily: "SF Pro Rounded, system-ui"
    fontSize: "28px"
    fontWeight: 700
  headline:
    fontFamily: "SF Pro, system-ui"
    fontSize: "15px"
    fontWeight: 600
  body:
    fontFamily: "SF Pro, system-ui"
    fontSize: "13px"
    fontWeight: 400
  metric:
    fontFamily: "SF Pro, system-ui"
    fontSize: "13px"
    fontWeight: 600
  label:
    fontFamily: "SF Pro, system-ui"
    fontSize: "11px"
    fontWeight: 500
  compact:
    fontFamily: "SF Pro, system-ui"
    fontSize: "9px"
    fontWeight: 500
rounded:
  sm: "6px"
  md: "8px"
  lg: "12px"
  xl: "16px"
spacing:
  "2": "2px"
  "4": "4px"
  "6": "6px"
  "8": "8px"
  "12": "12px"
  "16": "16px"
  "20": "20px"
  "24": "24px"
components:
  metric-tile:
    backgroundColor: "{colors.monitor-blue} at 4% opacity"
    textColor: "{colors.monitor-blue}"
    rounded: "{rounded.md}"
    padding: "{spacing.12}"
  card-panel:
    backgroundColor: "primary.opacity(0.03)"
    rounded: "{rounded.md}"
    padding: "{spacing.16}"
  card-material:
    backgroundColor: ".regularMaterial"
    rounded: "{rounded.sm}"
    padding: "{spacing.8} to {spacing.12}"
---

# Design System: RowPlay Studio

## 1. Overview

**Creative North Star: "The Erg Display"**

RowPlay Studio channels the clarity of the Concept2 PM5 performance monitor — a display designed for one purpose: showing athletes their numbers without distraction. The design is clean and focused, with color serving meaning rather than decoration. Every hue maps to a specific metric role (distance, pace, watts, heart rate), just as the PM5's LCD uses color sparingly to orient the athlete mid-effort.

The system is intentionally restrained: flat surfaces with tonal layering via macOS materials and subtle opacity, not shadows or depth effects. Typography uses system fonts for native feel, with SF Pro Rounded reserved for hero metrics to signal "this is the number that matters." Spacing follows an 8-point soft grid with generous breathing room — the athlete is analyzing their data, not scanning a dashboard.

This system explicitly rejects the Strava/Garmin fitness-app aesthetic: no dark/black backgrounds, no gamification badges, no social feed clutter, no gradient text, no glassmorphism, and no hero-metric-card templates. It is a tool for the dedicated athlete, not a casual fitness tracker.

**Key Characteristics:**
- Metric-first: color, typography, and layout serve the numbers
- Flat with tonal layering: macOS materials and opacity, no shadows
- Semantic color: each color maps to exactly one metric domain
- System-native: SF Pro as the single typeface, AppKit-conformant controls
- Quiet energy: color accents are deliberate and sparing, not decorative

## 2. Colors: The PM5 Palette

A six-color semantic palette, each named for its role on the erg display. Light and dark variants exist for every color; the dark variant is always slightly brighter and more saturated to maintain energy on dark backgrounds.

### Primary
- **Monitor Blue** (#0066CC / dark #0A84FF): Distance and primary actions. The PM5's signature blue — used for distance metrics, primary buttons, selected states, and the accent color role. Also carries pace variants at slightly lighter blue.
- **Duration Teal** (#007A99 / dark #64D2FF): Time and duration. Sits between blue and green — distinct enough from Monitor Blue that pace and distance are visually separable, but still cool and measured.

### Accent
- **Split Orange** (#9A5700 / dark #FF9F0A): Watts, speed, and splits. The warm amber of a PM5's split display. Used for all power-related metrics and comparison data.
- **Green Zone Green** (#137333 / dark #30D158): Positive deltas and target zones. The green of hitting your target. Reserved for success signals, improvement indicators, and cadence highlights.
- **Red Zone Red** (#B3261E / dark #FF453A): Heart rate and negative deltas. The PM5's ceiling indicator. Used for heart rate metrics, finish markers, and regression signals.
- **Cadence Violet** (#7B2CBF / dark #BF5AF2): Cadence and secondary rhythm metrics. The outlier hue — used sparingly for stroke rate and cadence to give them their own visual channel.
- **Caution Amber** (#7A5A00 / dark #FFD60A): Warning states and active indicators. The yellow of "pay attention." Used for caution status, live-mode active indicators, and sync-in-progress states.

### Named Rules
**The Metric Mapping Rule.** Each color maps to exactly one metric domain. Never use Split Orange for distance or Monitor Blue for heart rate. The athlete builds muscle memory with these color associations; inconsistency undermines trust.

## 3. Typography

**Display Font:** SF Pro Rounded (system, with SF Pro fallback)
**Body Font:** SF Pro (system)
**Label/Mono Font:** SF Pro (system, monospacedDigit variant for numbers)

**Character:** A single typeface family across the app, with SF Pro Rounded used only for hero metrics. This creates a clear hierarchy: rounded = "this is the headline number." Everything else is standard SF Pro at restrained weights. Numbers use `.monospacedDigit()` so columns align during comparison.

### Hierarchy
- **Hero** (bold, 28pt, 1.2 line-height): The primary metric value in summary cards and detail headers. SF Pro Rounded. Used exactly once per card/panel.
- **Headline** (semibold, 15pt, 1.3 line-height): Section titles and panel headers. SF Pro, standard design.
- **Body** (regular, 13pt, 1.4 line-height): Supporting text, descriptions, workout metadata. Max line length 65–75ch when in prose contexts.
- **Metric** (semibold, 13pt, 1.2 line-height): Data values in badges, tiles, and comparison panels. Monospaced digit variant.
- **Label** (medium, 11pt, 1.3 line-height): Labels beneath metric values. Secondary text color.
- **Compact** (medium, 9pt, 1.2 line-height): Tight spaces — sidebar badges, comparison deltas, annotation timestamps.

### Named Rules
**The One Hero Rule.** SF Pro Rounded appears on at most one element per card. If every number is rounded, none of them matter.

## 4. Elevation

RowPlay Studio is intentionally flat. Depth is conveyed through tonal layering — macOS `.regularMaterial` for elevated cards, subtle opacity overlays for grouped backgrounds — rather than shadows or z-axis effects. This keeps the interface calm and reinforces the PM5-monitor aesthetic where everything exists on one plane.

No drop shadows, no box shadows, no elevation tokens. Surfaces differentiate via background opacity: the window chrome is `.clear`, chart panels sit on `primary.opacity(0.03)`, and material cards float at `.regularMaterial`. The active/selected state uses `accentColor.opacity(0.08)`.

### Named Rules
**The Flat-By-Default Rule.** No shadows, ever. Depth is tonal, not spatial. If a surface needs to feel elevated, use a more opaque macOS material; never add `shadow()`.

## 5. Components

### Metric Tiles
Dashboard summary cards displaying a single headline metric. Clean, icon-led, no decoration.

- **Shape:** 8pt radius (`RoundedRectangle(cornerRadius: 8)`)
- **Background:** `.regularMaterial` with optional metric color at low opacity
- **Typograpy:** SF Pro Rounded bold for the value, SF Pro medium for the label
- **States:** No hover or active state — tiles are read-only display surfaces
- **Accessibility:** `.accessibilityElement(children: .ignore)` with explicit label and value

### Card Panels
Chart containers and grouped content sections.

- **Shape:** 8pt radius
- **Background:** `primary.opacity(0.03)` (`panelBackground`)
- **Internal padding:** 16pt
- **Border:** None
- **Header:** Section headline typography, left-aligned

### Material Cards
Sport summary and personal best cards. Elevated from the scroll background.

- **Shape:** 6pt radius (sm) or 8pt (md) depending on context
- **Background:** `.regularMaterial`
- **Internal padding:** 8–12pt depending on density needs
- **Content:** Icon + label header row, metric value, supporting stat line

### Navigation (Sidebar)
Native macOS NavigationSplitView sidebar with workout list.

- **Style:** System-default sidebar with `.sidebar` list style
- **Typography:** SF Pro, default weight for workout titles, secondary color for metadata
- **States:** System default selection highlight (accent color)
- **Width:** Minimum 260pt, ideal 320pt

### Segmented Picker
Sport filter in the toolbar, filtering workouts by RowErg / SkiErg / BikeErg.

- **Style:** `.segmented` picker style, 280pt wide
- **Options:** "All" + one per sport, using sport display names
- **Behavior:** Filters sidebar list and dashboard metrics immediately

### Empty State
ContentUnavailableView shown when no workouts exist.

- **Icon:** `figure.rower` SF Symbol
- **Title:** "No Workouts"
- **Description:** Guides user to enable demo mode or sync real data
- **Behavior:** Triggers when library is empty and demo mode is off

## 6. Do's and Don'ts

### Do:
- **Do** use Monitor Blue exclusively for distance, primary actions, and accent color — never for heart rate or watts
- **Do** use Split Orange for watts, speed, and split time — the athlete expects warm tones for power metrics
- **Do** use SF Pro Rounded only for hero metric values — at most one per card
- **Do** keep surfaces flat with tonal layering via macOS materials and opacity
- **Do** use `.monospacedDigit()` for all numeric metric displays so columns align
- **Do** provide `.accessibilityLabel()` and `.accessibilityValue()` on every metric tile with `.accessibilityElement(children: .ignore)`

### Don't:
- **Don't** use dark or black backgrounds — avoid the Strava/Garmin dark fitness-app aesthetic
- **Don't** add gamification badges, challenge counters, or social feed elements — this is an analysis tool, not a social platform
- **Don't** use gradient text, glassmorphism, or decorative blurs
- **Don't** use the hero-metric template (big number, small label, supporting stats, gradient accent) as a default card pattern
- **Don't** use border-left or border-right stripes greater than 1px as colored accents on cards
- **Don't** add shadows to any surface — depth is tonal, not spatial
- **Don't** use identical icon + heading + text card grids as a default content layout
- **Don't** cross-assign semantic colors — Split Orange on distance metrics undermines the athlete's visual vocabulary
