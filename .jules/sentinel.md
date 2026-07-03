## 2026-07-03 - ReDoS Prevention in Input Parsers
**Vulnerability:** User-entered pace strings and day/logbook keys were passed directly to `try! NSRegularExpression(...).firstMatch(in:)` without length limits. A maliciously crafted, exceedingly long string could cause a Denial of Service (ReDoS) by consuming significant CPU or memory.
**Learning:** Even simple regexes can become performance bottlenecks if the input length is unbound, particularly if the string operations (like `Range` creation and regex evaluation) scale with input size.
**Prevention:** Always bound the input string's length (`.count <= MAX_EXPECTED_LENGTH`) *before* executing regex, especially on paths handling untrusted or user-entered data like `PaceInput`.
