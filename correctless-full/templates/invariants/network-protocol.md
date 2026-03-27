# Network Protocol Invariant Template

When a feature involves network communication, TLS, or protocol handling, the /cspec skill should ensure the spec addresses each of the following concerns.

## Checklist

For each applicable item, draft a starter invariant. Skip items that don't apply — but note why.

### 1. Outbound connections use dialer abstraction

- **Check**: All outbound connections are made through a configurable dialer or transport abstraction, never by calling `net.Dial` or `http.DefaultClient` directly.
- **Violated when**: A feature hardcodes `net.Dial` or uses `http.DefaultTransport`, making it impossible to inject timeouts, proxy configuration, DNS resolution, or test doubles without modifying the feature code.
- **Starter invariant**: "INV-NET-001: All outbound connections in this feature must use the project's dialer/transport abstraction, never raw net.Dial or http.DefaultClient."
- **Test approach**: Grep for direct `net.Dial`, `http.DefaultClient`, and `http.DefaultTransport` usage in the feature's package. Write tests using a mock dialer to verify the feature routes all connections through the abstraction.

### 2. TLS validation is explicit

- **Check**: TLS certificate validation is explicitly configured — never relying on implicit defaults, and never disabled without a build-tag or environment gate that prevents it from reaching production.
- **Violated when**: `InsecureSkipVerify: true` is set unconditionally, or TLS configuration is omitted entirely (relying on defaults that may differ across environments), or a debug flag disables verification without compile-time or environment constraints.
- **Starter invariant**: "INV-NET-002: TLS validation in this feature must be explicitly configured. InsecureSkipVerify must never be true in production builds; any skip must be gated by a build tag or environment check."
- **Test approach**: Grep for `InsecureSkipVerify`. Write a test that attempts to connect to a server with an invalid certificate and assert the connection is rejected in the default configuration. If a skip mode exists, verify it is gated.

### 3. SNI/hostname distinguishes untrusted vs verified

- **Check**: The TLS Server Name Indication (SNI) value is set explicitly and matches the expected hostname. The feature distinguishes between the hostname used for connection routing (potentially untrusted, e.g., from a proxy or redirect) and the hostname verified by TLS.
- **Violated when**: SNI is derived from an untrusted source (user input, redirect target) without validation, allowing an attacker to direct traffic to a malicious server that presents a valid certificate for a different domain, or hostname verification is skipped after a redirect.
- **Starter invariant**: "INV-NET-003: TLS SNI in this feature must be set to the verified target hostname, not derived from untrusted routing information. Hostname verification must apply after redirects."
- **Test approach**: Configure a test server with a certificate for domain A and attempt to connect using SNI for domain B. Assert the connection fails. Test redirect scenarios to verify hostname verification is re-applied against the redirect target.

### 4. Timeouts on all network paths

- **Check**: Every network operation has an explicit timeout — dial, TLS handshake, request/response, and idle connection — with values that are documented, configurable, and appropriate for the operation.
- **Violated when**: Any network path can block indefinitely — a dial with no timeout against an unresponsive host, a TLS handshake that hangs, a response body read with no deadline, or an idle connection that is never reaped — causing goroutine and connection leaks.
- **Starter invariant**: "INV-NET-004: Every network path in this feature (dial, TLS handshake, request, response body read, idle) must have an explicit, configurable timeout. No path may block indefinitely."
- **Test approach**: For each network phase, introduce artificial latency (via mock transport or iptables) exceeding the configured timeout and assert the operation fails with a timeout error within the expected bound. Verify no goroutine or connection leaks after timeout.

### 5. Proxy preserves or strips security headers correctly

- **Check**: When this feature acts as or communicates through a proxy, security-sensitive headers (Authorization, Cookie, X-Forwarded-For, Host) are explicitly handled — preserved when required for upstream authentication, stripped when forwarding to untrusted destinations.
- **Violated when**: An Authorization header is forwarded through a proxy to a redirected third-party host, leaking credentials. Or X-Forwarded-For is accepted from an untrusted client without validation, allowing IP spoofing. Or Host header is not rewritten, causing routing errors or host-header attacks.
- **Starter invariant**: "INV-NET-005: This feature must explicitly document which security headers are preserved, stripped, or rewritten at each proxy hop, with different rules for trusted vs untrusted destinations."
- **Test approach**: Send requests through the proxy with security-sensitive headers, redirect to an untrusted destination, and capture the forwarded request. Assert that credentials are stripped, X-Forwarded-For is validated/appended correctly, and Host is rewritten.
