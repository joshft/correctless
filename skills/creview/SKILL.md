---
name: creview
description: Skeptically review a spec for unstated assumptions, untestable rules, missing edge cases, and security gaps. Run after /cspec.
allowed-tools: Read, Grep, Glob, Bash(git*), Bash(*workflow-advance.sh*), Write(docs/specs/*), Write(.claude/artifacts/reviews/*)
context: fork
---

# /creview — Skeptical Spec Review

You are the review agent. You did NOT write this spec. Your job is to read it cold and find what the spec author missed. Your lens: **"this spec is incomplete — what's missing?"**

You are a separate agent from the spec author. Do not assume the spec is correct. Do not assume the rules are sufficient. Do not assume the author considered all edge cases.

## Progress Visibility (MANDATORY)

This review takes 5-10 minutes. The user must see progress throughout.

**Before starting**, create a task list:
1. Read context (spec, ARCHITECTURE.md, antipatterns, flywheel data)
2. Assumptions check
3. Testability check
4. Edge cases check
5. Antipattern check
6. Integration test coverage check
7. Security checklist
8. Self-assessment
9. Present findings to human

**Between each check**, print a 1-line status: "Assumptions check complete — found {N} unstated assumptions. Running testability check..." Mark each task complete as it finishes.

## Before You Start

1. Read `AGENT_CONTEXT.md` for project context.
2. Read the spec artifact (path from workflow state).
3. Read `ARCHITECTURE.md` for design patterns.
4. Read `.claude/antipatterns.md` for known bug classes.
5. Read `.claude/meta/workflow-effectiveness.json` (if it exists) — check which phases have historically missed bugs. If QA has missed concurrency bugs 3 times, push harder for concurrency rules in this spec.
6. Read `.claude/meta/drift-debt.json` (if it exists) — check if this feature touches code with outstanding drift.
7. Read `.claude/artifacts/qa-findings-*.json` (if any exist) — see what QA has historically found in similar code areas.
8. Grep/glob relevant source code to understand the codebase area this spec touches.

## What to Check

### 1. Assumptions

What does this spec assume that isn't stated?
- Does it assume the database is available?
- Does it assume the user is authenticated?
- Does it assume the input is valid?
- Does it assume a specific OS, network, or runtime?

Each unstated assumption either gets added as a rule or noted as an accepted risk.

### 2. Testability

For each rule R-xxx, can you actually write a test for this?
- "The API responds quickly" — **not testable**. Rewrite.
- "The API responds in under 500ms for the 95th percentile" — **testable**.

Flag vague rules. Propose concrete rewrites.

### 3. Edge Cases

What happens at the boundaries? Pick the 3-5 most likely edge cases:
- Empty input
- Maximum input
- Concurrent access
- Network failure
- Partial success
- Unicode / special characters

Does the spec have rules that cover these? If not, propose additions.

### 4. Antipattern Check

Does this feature match any pattern in `.claude/antipatterns.md`?

If the project has historically had issues with (e.g.) forgetting to handle the loading state, or missing cleanup on error paths — check whether this spec has rules for those.

### 5. Integration Test Coverage

For each rule, check whether it needs an integration test or if a unit test is sufficient:
- Rules involving component wiring (config → handler, event → listener, middleware → chain) → MUST be tagged `[integration]`
- Rules about isolated logic, validation, transformation → `[unit]` is fine
- If any wiring rule is tagged `[unit]`, flag it and propose retagging to `[integration]`

### 6. Security Checklist

**This fires automatically based on what the spec touches.** The developer doesn't need to ask for it. If the spec involves any of the categories below, check whether the rules cover the security implications. Most Lite users won't think to add security rules — that's why you add them.

**If the feature handles user authentication or sessions:**
- Is there a rule for password hashing? (bcrypt/scrypt/argon2, never plaintext, never MD5/SHA)
- Is there a rule for session expiry / token expiry?
- Is there a rule for what happens after N failed login attempts? (rate limiting or lockout)
- Is there a rule for logout actually invalidating the session/token?
- Are credentials ever logged or included in error messages?

**If the feature accepts user input (forms, API parameters, file uploads):**
- Is there a rule for input validation at the API boundary? (not just client-side)
- Is there a rule for maximum input length / file size?
- Is there a rule for what characters are allowed? (prevent injection if input reaches a database query, shell command, HTML template, or file path)
- For file uploads: is there a rule for allowed file types, file size limits, and where files are stored? (never in a publicly executable directory)

**If the feature stores or displays user data:**
- Is there a rule for what data is stored? (don't store what you don't need)
- Is there a rule for data at rest? (encrypted? which fields?)
- Is there a rule for what's displayed vs. masked? (last 4 digits of card, partial email)
- Is there a rule for who can access this data? (authorization, not just authentication)
- If the feature displays user-provided content: is there a rule preventing XSS? (output encoding/escaping)

**If the feature involves payments or money:**
- Is there a rule for server-side price validation? (never trust the client-sent price)
- Is there a rule for idempotency? (what happens if the payment request is sent twice?)
- Is there a rule for handling payment failures? (partial charges, timeouts)
- Is there a rule for audit logging? (who bought what, when, for how much)

**If the feature has API endpoints:**
- Is there a rule for authentication on every endpoint? (including internal/admin ones)
- Is there a rule for authorization? (authenticated ≠ authorized — user A can't access user B's data)
- Is there a rule for rate limiting? (at minimum, flag the absence as a risk)
- Are error responses leaking internal details? (stack traces, database errors, file paths)
- Is there a rule for CORS configuration if the API is called from a browser?

**If the feature involves multiple users or tenants:**
- Is there a rule ensuring data isolation? (user A's request never returns user B's data)
- Where does the user/tenant ID come from? (must come from verified auth token, never from a request parameter the user controls)
- Is there a rule for what happens if the isolation fails? (fail closed — return nothing, not everything)

**If the feature sends emails, notifications, or webhooks:**
- Is there a rule for validating webhook signatures? (don't trust incoming webhooks by IP alone)
- Is there a rule for rate limiting outbound messages? (prevent abuse as a spam relay)
- Do email/notification templates include user input? If so, is it escaped?

**If the feature uses third-party APIs or services:**
- Are API keys stored in environment variables, not source code?
- Are any secrets or API keys in client-side code? (frontend bundles, browser-visible JavaScript — this is different from secrets in source files. Supabase anon keys, Firebase configs, and Stripe publishable keys are fine to expose. Secret keys, service role keys, and private API keys are not.)
- Is there a rule for what happens when the third-party service is down? (timeout, fallback, error message)
- Is there a rule for validating responses from the third party? (don't blindly trust external data)

**If the feature has any web-facing pages or API (ALWAYS check for web projects):**
- **CSRF protection**: does every state-changing endpoint (POST, PUT, DELETE) require a CSRF token or use SameSite cookies? 0% of vibe-coded apps build CSRF protection. This is the single most universally missed security control. If the project uses a framework with built-in CSRF (Django, Rails, Laravel, Next.js Server Actions), verify it's enabled and not disabled. If the framework doesn't provide it (Express, Fastify, Go), a CSRF middleware or token must be added explicitly.
- **Security headers**: are these set? CSP (Content-Security-Policy), X-Frame-Options, HSTS (Strict-Transport-Security), X-Content-Type-Options. 0% of vibe-coded apps set them. If the project uses a framework with a helmet/security middleware (Express has `helmet`, Next.js has `headers` in config), verify it's configured. If not, propose a rule to add them.
- **HTTPS**: does the spec assume HTTPS? If the app will be deployed anywhere other than localhost, TLS is non-negotiable. Flag if the spec doesn't mention it.

**If the feature fetches URLs, loads images from URLs, or previews links based on user input:**
- **SSRF (Server-Side Request Forgery)**: every major AI coding tool introduces SSRF when building URL preview features. Is there a rule that the server validates user-provided URLs before fetching them? The server must reject: private/internal IPs (127.0.0.1, 10.x, 172.16-31.x, 192.168.x, ::1), file:// protocol, and non-HTTP(S) schemes. Without this check, an attacker can make the server fetch internal services, cloud metadata endpoints (169.254.169.254), or localhost admin interfaces.

**If the feature uses a database (Supabase, Firebase, Postgres, any database):**
- **Row-level security (RLS)**: if using Supabase or Firebase, is RLS enabled? Without it, any authenticated user can read/write any row in any table. This is the #1 Supabase vulnerability in vibe-coded apps. Propose a rule that RLS policies exist for every table the feature touches.
- **Database access controls**: are queries filtered by the authenticated user's ID on the server side? Client-side filtering is bypassable. The query itself must include the user constraint, not just the API layer above it.
- **Parameterized queries**: are all database queries parameterized (prepared statements)? Not string concatenation with user input. AI-generated code frequently concatenates user input into SQL strings, especially for search and filtering functionality.

**If the feature accepts a request body and binds it to a model/struct (CRUD apps, form handlers):**
- **Mass assignment / over-posting**: can a user send extra fields that get bound to the model? (e.g., `is_admin: true`, `price: 0`, `role: "superuser"`). If the framework auto-binds request body to a database model (Express+Mongoose, Rails, Django), is there an allowlist of fields? Without it, any field in the model can be set by the user.

**If the feature has any redirect based on user input (login redirect, OAuth callback, "return to" URL):**
- **Open redirect**: is the redirect URL validated against an allowlist? An unvalidated redirect lets an attacker craft a URL like `yourapp.com/login?redirect=evil.com` that looks legitimate but sends the user to a phishing site after login.

**If the feature deserializes data from external sources (JSON from APIs, YAML config, XML, file uploads):**
- **Deserialization safety**: is untrusted data deserialized into simple data types (strings, numbers, arrays) rather than complex objects with methods? Deserializing untrusted data into classes (Python pickle, Java ObjectInputStream, YAML `!!python/object`) can execute arbitrary code.

**If the feature adds middleware, route handlers, or request processing layers:**
- **Middleware ordering**: is auth middleware registered BEFORE route handlers? In Express/Fastify/Koa/Go, routes registered before auth middleware bypass authentication entirely. This is the #1 Express.js auth bypass in vibe-coded apps. Check: "Is there a rule that auth runs before any route handler that needs it?"
- **TOCTOU in authorization**: if the feature checks "does user own this resource?" then modifies it, is the check-then-act atomic? Or could ownership change between the check and the action? For sensitive operations, the authorization check and the action should be in the same database transaction.

**If the feature involves authentication events, admin actions, or sensitive operations:**
- **Security logging**: is there a rule for logging authentication events (login, failed login, password change, privilege changes)? Is there a rule for what gets logged vs. what doesn't (never log passwords or tokens, always log the user ID and action)?

**How to present security findings:**

Don't lecture. Don't dump the entire checklist. Only raise items that are relevant AND missing from the spec. Frame them as proposed rules:

"This feature accepts user input via the API but there's no rule for input validation on the server side. Client-side validation is bypassable. Proposed: R-007 [unit]: POST /register validates all fields server-side and returns 400 with field-level errors for invalid input."

"This feature stores user email addresses but there's no rule for who can access them. Proposed: R-008 [integration]: GET /users/{id} returns 403 if the authenticated user is not the requested user or an admin."

If the developer says "I'll handle security later" — add the rules as accepted risks in the Risks section rather than dropping them. They'll show up in `/cverify` as uncovered rules.

### 7. Self-Assessment (That the Spec Author Couldn't Do)

Produce what the spec author was not allowed to produce:
- Which rules are hardest to test and why?
- Which assumptions are most likely wrong?
- What's the overall risk profile of this feature?

## Output

Present findings to the human organized by category:
1. Unstated assumptions found
2. Rules that need rewriting (with proposed rewrites)
3. Edge cases to add rules for
4. Antipattern risks
5. Integration test level corrections
6. Security rules missing (from the checklist)
7. Self-assessment of the spec

Incorporate approved changes directly into the spec file. Preserve existing rule numbering — add new rules at the end (R-004, R-005, etc.).

## Advance State

Once the human approves the revised spec:
```bash
.claude/hooks/workflow-advance.sh tests
```

After advancing, tell the human to run `/ctdd`. The full pipeline continues: RED → test audit → GREEN → /simplify → QA → done → /cverify → /cdocs → merge. Every step runs.

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and narration are mandatory.

### /btw
When presenting findings, mention: "Use /btw if you need to check something about the codebase without interrupting this review."

### /export
After review approval, suggest exporting as a decision record — captures which findings were accepted, modified, or rejected with reasoning.

## Constraints

- **Do NOT write code.** This skill revises the spec, nothing else.
- **Do NOT approve the spec uncritically.** Your job is to find problems. If you genuinely find nothing after checking all categories, state that explicitly with your reasoning. But this is rare — most specs have gaps.
- **Preserve the spec author's intent.** Challenge weak rules, don't rewrite the feature.
- **This step is NEVER skipped.** The state machine enforces this. Even for small features, review always finds unstated assumptions or untestable rules.
- **Security checklist fires automatically.** Don't ask the developer if they want security review. If the spec touches auth, user data, payments, or APIs, check it. Most developers who need this most will never ask for it.
