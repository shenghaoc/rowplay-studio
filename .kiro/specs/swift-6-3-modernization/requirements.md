# Requirements: Swift 6.3 Modernization

## Purpose

Make Swift 6.3.3 and macOS 26 the explicit repository baselines, then complete the language-mode, concurrency, and CI migration.

## Requirements

### R1: Toolchain and Language Mode

- `Package.swift` MUST use Swift tools version 6.3 and explicitly select Swift language mode 6.
- `.swift-version` MUST pin Swift 6.3.3 for compatible local toolchain managers.
- The package MUST target macOS 26 or newer.

### R2: Checked Concurrency

- Production and mock code MUST compile under Swift 6.3.3 with complete Swift 6 language-mode concurrency checks.
- Mutable in-memory state MUST use checked synchronization rather than `nonisolated(unsafe)` or broad `@unchecked Sendable` conformances.
- Mutable state MUST use Swift's `Synchronization.Mutex` on both macOS and Linux.
- Raw SQLite handles MAY retain narrowly documented `@unchecked Sendable` conformances when every access remains confined to the existing private serial queue.

### R3: Modern APIs and Sendability

- Stateless namespace enums and safe error/value types MUST declare `Sendable` where applicable.
- ISO-8601 formatting MUST use the value-typed `Date.ISO8601FormatStyle` API.
- XCTest lifecycle overrides and UI-facing tests MUST respect actor isolation without unsafe annotations.

### R4: CI Enforcement

- Linux CI MUST run on Ubuntu 24.04 with Swift 6.3.3 and SQLite development headers.
- macOS CI MUST run on macOS 26 with Xcode 26.6 and Swift 6.3.3.
- Both CI jobs MUST fail if the active compiler is not Swift 6.3.3.
- Build and test commands MUST treat Swift compiler warnings as errors.
- Linux MUST continue to build and test the cross-platform `RowPlayCore` graph; macOS MUST continue to test and build the full package.

## Non-Goals

- No support for macOS releases earlier than macOS 26.
- No product behavior or UI changes.
- No SQLite schema or persistence changes.
- No adoption of Swift 6.3 features that do not fit the project, such as C exports or unmeasured specialization attributes.
