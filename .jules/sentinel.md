## 2026-07-03 - ReDoS Prevention in Input Parsers
**Vulnerability:** User-entered pace strings and day/logbook keys were passed directly to `try! NSRegularExpression(...).firstMatch(in:)` without length limits. A maliciously crafted, exceedingly long string could cause a Denial of Service (ReDoS) by consuming significant CPU or memory.
**Learning:** Even simple regexes can become performance bottlenecks if the input length is unbound, particularly if the string operations (like `Range` creation and regex evaluation) scale with input size. Use `utf16.count` to match `NSRegularExpression`'s UTF-16 basis.
**Prevention:** Always bound the raw input length before trimming or executing regex, especially on paths handling untrusted or user-entered data, then bound the trimmed value before regex. Applied raw limits of 64 UTF-16 code units plus trimmed limits for `PaceInput.parsePaceInput` (20, max valid ~18 chars), `RowPlayDateTime.parseLogbookParts` (30, max valid 19 chars), and `RowPlayDateTime.parseDayKey` (20, max valid 10 chars).

## 2026-07-04 - CSV Formula Injection Evasion via Whitespace
**Vulnerability:** The existing CSV Formula Injection protection checked the very first character of the input string for formula triggers (`=`, `+`, etc.). This could be bypassed by an attacker adding leading whitespace (e.g., ` =cmd|...`), which spreadsheet software like Excel trims before evaluating the formula.
**Learning:** Checking the first character of an un-trimmed string is insufficient for CSV injection protection because spreadsheet parsers are robust against leading whitespace. Furthermore, the OWASP recommended prefix is a single quote (`'`), not a tab character (`\t`).
**Prevention:** Always strip leading whitespace before determining if the string begins with a formula trigger character. If it does, prepend a single quote (`'`) to the original string.

## 2026-07-05 - Unencrypted Sensitive Data Transmission
**Vulnerability:** The Concept2 client allowed configuring an arbitrary `baseURL` which could use the plain HTTP scheme. By doing so, the user's secret BYOT `Bearer` token could be sent over the network in cleartext without TLS encryption, leading to potential token interception and account takeover.
**Learning:** Network clients appending Bearer tokens or sensitive headers shouldn't blindly trust that the base URL provides transport layer security.
**Prevention:** Always assert or guard that the final URL scheme is `https` before attaching authentication headers to the `URLRequest`. Fail securely if the scheme is `http`.

## 2026-07-06 - Uncontrolled Resource Consumption (DoS) via Default URLSessionConfiguration
**Vulnerability:** The HTTP transport created for API calls relied on `URLSessionConfiguration.default`, which has a very high `timeoutIntervalForResource` (7 days) and a generic `timeoutIntervalForRequest` (60 seconds). This could lead to resource exhaustion if connecting to a slow or hanging server.
**Learning:** Default configuration parameters may not be suited for robust network interactions where prompt failure is preferred over indefinitely tied-up resources.
**Prevention:** Explicitly configure timeout limits on any `URLSessionConfiguration` that will be used to initialize a `URLSession`, setting strict thresholds for both `timeoutIntervalForRequest` and `timeoutIntervalForResource`.

## 2026-07-07 - CSV Formula Injection Evasion via Newlines
**Vulnerability:** The existing CSV Formula Injection protection checked the very first character of the input string for formula triggers (`=`, `+`, etc.) after trimming `.whitespaces`. This could still be bypassed by an attacker adding leading newline characters (e.g., `\n=cmd|...`), which spreadsheet software like Excel handles and then evaluates the formula.
**Learning:** Checking the first character of a string trimmed only by `.whitespaces` is insufficient for CSV injection protection because spreadsheet parsers are robust against leading newlines and tabs.
**Prevention:** Always strip leading whitespaces AND newlines before determining if the string begins with a formula trigger character. Use `.whitespacesAndNewlines` instead of `.whitespaces`.

## 2026-07-08 - Token Leak via HTTPS Redirect to Different Host
**Vulnerability:** The HTTP transport created for API calls only rejected redirects to non-HTTPS URLs. It allowed redirects to different hosts as long as they were HTTPS. This could lead to a token leakage if a server returned a redirect to an attacker-controlled HTTPS server, and the token was attached to the redirect request.
**Learning:** Checking the scheme of the redirect URL is not sufficient to prevent token leakage. An attacker could set up an HTTPS server and redirect the client to it, capturing the bearer token.
**Prevention:** Ensure that redirects are only allowed if the new URL has the same host as the original request, in addition to being HTTPS. Compare hosts case-insensitively (RFC 3986) and require both hosts to be non-nil so malformed URLs do not pass a `nil == nil` check. If the host is different or missing, block the redirect.

## 2026-07-09 - ReDoS Prevention in Generic Redaction Loggers
**Vulnerability:** The `PrivacySafeLogger.swift` applied multiple regex patterns (`NSRegularExpression`) sequentially against potentially unbounded input string data before logging. Payloads with many nested braces or brackets matching complex regex patterns with nested quantifiers (e.g., `#"\{(?:[^{}]|\{[^{}]*\}){100,}\}"#`) could cause severe ReDoS (Regular Expression Denial of Service) by exploiting exponential backtracking.
**Learning:** Even if some specific inputs like user-entered dates or paces have explicit length limits applied in their respective validation layers, generic functions like loggers receive arbitrary application data (e.g., huge JSON payloads or errors) that must also be strictly bound before regex processing.
**Prevention:** Bound the length of input strings globally in generic redaction utilities. For logging, if an input exceeds a safe threshold (e.g., 16KB / 16384 characters), truncate the string to the safe bound and append a ` [TRUNCATED]` marker. This preserves the prefix of the log message for troubleshooting while preventing ReDoS on the regex engine.

## 2026-07-10 - Sensitive Data Exposure via Default URLSessionConfiguration Caching
**Vulnerability:** The `URLSessionHTTPTransport` used `URLSessionConfiguration.default`, which wires the shared disk-backed `URLCache`, `HTTPCookieStorage`, and `URLCredentialStorage`. Cached Concept2 API response bodies (workout/profile payloads) and any cookies or URL-authentication credentials can therefore persist under the app's Caches directory. If a device is compromised, that data can be extracted offline.
**Learning:** `URLSessionConfiguration.default` silently persists session-related material to disk. Bearer tokens carried only in the `Authorization` header are not themselves written by the shared credential store, but response bodies and cookies still are — and that is enough to leak sensitive user data. Concept2 tokens and payloads must not depend on shared on-disk session stores.
**Prevention:** Use `URLSessionConfiguration.ephemeral` (see `URLSessionHTTPTransport.makeSecureConfiguration()`) for token-bearing API clients. Optionally set `urlCache`, `httpCookieStorage`, and `urlCredentialStorage` to `nil` for defense in depth, and keep strict request/resource timeouts. Never use the shared disk-backed defaults for authenticated Concept2 traffic.
