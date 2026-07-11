# Design: Swift 6.3 Modernization

## Overview

The package manifest now requires tools version 6.3 and explicitly selects Swift language mode 6. A repository `.swift-version` file and CI assertions pin the concrete 6.3.3 toolchain so a newer runner default cannot silently change the baseline.

## Checked Synchronization

Swift 6.3's `Synchronization.Mutex` provides the same checked, state-owning synchronization primitive on macOS 26 and Linux.

Mutable in-memory stores, mocks, redirect tracking, task-reference coordination, and shared `DateFormatter` instances hold their entire mutable state inside the lock. This removes the previous `nonisolated(unsafe)` closure capture and most broad `@unchecked Sendable` declarations. The two SQLite stores retain their existing queue-confined unchecked conformance because their raw C handles cannot express checked sendability.

`RowPlayDateTime` uses `Date.ISO8601FormatStyle` for ISO output, avoiding a shared non-Sendable `ISO8601DateFormatter` entirely.

## Actor-Isolated XCTest Setup

Main-actor platform test classes use XCTest's async `setUp()` and `tearDown()` overrides, which inherit actor isolation correctly under the Swift 6.3 XCTest overlay. The Studio test class is explicitly main-actor isolated before calling a SwiftUI view helper.

## CI

The Linux lane installs or selects Swift 6.3.3 and installs `libsqlite3-dev`. The macOS lane selects the verified `/Applications/Xcode_26.6.app` image alias. Both lanes assert the compiler version and pass `-Xswiftc -warnings-as-errors` to their build and test gates.

The runner split remains unchanged: Linux validates the Core-only graph and macOS validates the full Core, Platform, and Studio package.

## Compatibility

The package deployment target is macOS 26, and the Core target continues to compile on Linux.
