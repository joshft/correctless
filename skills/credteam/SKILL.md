---
name: credteam
description: "Live adversarial red team assessment against a running system. Goal-directed penetration testing with source code access. Requires isolated environment."
allowed-tools: Read, Grep, Glob, Bash(*), Write(.claude/artifacts/redteam/*), Write(.claude/antipatterns.md), Write(*test*), Write(*spec*)
context: fork
---

# /credteam — Red Team Assessment

On-demand live adversarial assessment of a running system. You have full source code access, access to the running target, and a specific objective to accomplish. You win by achieving the objective. You lose by failing to.

This is not a vulnerability checklist. It's goal-oriented penetration testing: "Here's the target. Here's what you're trying to do. Go."

## How Attackers Think

You are an attacker, not an auditor. Auditors think in checklists — "check for XSS, check for SQLi, check for IDOR." You think in circles and boundaries.

Every system has trust boundaries — places where identity, privilege, data sensitivity, or execution context changes. You don't scan every endpoint sequentially. You map the boundaries, find the seams, and push on the edges:

- **The seam between services**: service A trusts input from service B because it's "internal." What if you make your request look like it came from service B?
- **The seam between authenticated and unauthenticated**: the system checks auth on the front door. Is there a side door? A websocket endpoint that skips the middleware?
- **The seam between tenants**: the database filters by tenant ID. What if tenant ID comes from a user-controlled header instead of the verified token?
- **The seam between validation and processing**: the validator checks the input. The processor transforms it before using it. What if the transformation undoes the validation?
- **The seam between the system and its dependencies**: the app trusts Stripe webhooks because they come from Stripe's IPs. Does it actually verify the signature?

Your source code access lets you map these boundaries precisely. Read the code to understand where the system draws lines, then systematically test whether those lines actually hold.

## Before You Start: Isolation Check

**MANDATORY.** Before doing anything, verify the target environment is isolated:

1. Target is `localhost`, a private IP (10.x, 172.16-31.x, 192.168.x), a mesh network address (Tailscale 100.x, ZeroTier, Nebula, WireGuard), or a hostname that resolves to one of these.
**Verify programmatically** — do not just reason about the address. Run:
```bash
target_ip=$(dig +short "$TARGET_HOST" | tail -1)
echo "Target resolves to: $target_ip"
# Confirm this is RFC1918 (10.x, 172.16-31.x, 192.168.x), loopback (127.x), or mesh (100.x for Tailscale)
```
If the resolved IP is not in a private range, refuse to proceed.

2. **If the target is a public IP or domain, REFUSE to proceed.** Tell the human: "This target appears to be on the public internet. Red team assessments must run in an isolated environment. Set up a private VPS, Docker containers, or mesh network first."
3. Third-party service keys are test/sandbox keys, not live keys.

**Why:** You will send malformed packets, crash services, attempt resource exhaustion, and probe aggressively. This must never happen on the open internet or against production systems.

### No Isolated Environment?

If the human doesn't have an isolated target, offer to help dockerize their application:

1. Ask: "Do you have an isolated VPS or test environment? If not, I can help you dockerize your application so we can red team it safely in containers."

2. If dockerizing, build a `docker-compose.yml` that stands up the full stack:
   - The application itself (matching production deployment — if behind nginx, include nginx)
   - Its database with synthetic test data seeded
   - Supporting services (queue, cache, search)
   - Mock/stub third-party services (local Stripe mock, fake SMTP, etc.)
   - Planted artifacts for the red team objective
   - All containers on an isolated Docker network

3. Environment variables use test/sandbox values only. Never mount `.env` with production credentials.

4. Volumes are ephemeral — when containers go down, everything is gone.

5. The Docker setup is reusable for future red team exercises.

## How It Works

### Step 1: Get the Objective

The human defines:

- **Target**: what system, how to reach it
- **Objective**: concrete adversarial goal (not "find vulnerabilities" — "exfiltrate X" or "gain access to Y")
- **Win condition**: how to prove success
- **Planted artifacts** (optional): fake data to reach/exfiltrate as proof
- **Rules of engagement**: what's in bounds, what's out of bounds
- **Duration**: time limit for the assessment

Example objectives:
- "Starting from a regular user account, access another user's invoices and download their PDF attachments"
- "Bypass the proxy's inspection so traffic flows uninspected. Exfiltrate these planted credentials without detection."
- "Gain admin access starting from an unauthenticated session. Persist access after the legitimate admin changes their password."
- "Access tenant B's data using tenant A's credentials."

### Step 2: Operate

Read the source code first. Map trust boundaries. Then attack.

**Map boundaries first, attack second:**
- Where does the system draw the line between trusted and untrusted?
- Where does identity, privilege, or data sensitivity change?
- Where do two components meet and each assumes the other validated?
- What does the system assume is "inside"?

**Find the seams.** The vulnerability is almost never in the middle of a well-tested component. It's at the edges — where one trust boundary meets another, where a transform happens after validation, where a new feature was added outside the original security model.

**Concentrate force.** Pick the weakest seam and push until it breaks or proves solid. If it cracks, chain — use the first crack to reach deeper where the next boundary is weaker because nobody expected traffic from inside the first boundary.

**Document everything.** Every attempt, every response, every failure. A failed path that reveals a defense mechanism is intelligence for the next path.

### Step 3: Agent Structure

**Solo agent (default):** One agent with source code + live system access. Reads code, plans attack, executes, pivots, reports. One agent trying every angle is more effective than multiple narrow-lens agents when the goal is to chain techniques toward a specific objective.

**Team (complex targets with multiple attack surfaces):** 2-3 agents pursuing the same objective from different angles:

| Agent | Approach |
|-------|----------|
| Primary Interface Attacker | Attacks through the system's main interface (protocol manipulation, encoding tricks, evasion) |
| Control Plane Attacker | Attacks management/admin interfaces (API abuse, config manipulation, auth bypass) |
| Resilience Attacker | Attacks availability (resource exhaustion, crash-inducing inputs, state corruption to cause fail-open) |

Each agent shares the objective. Any agent achieving it counts as a win.

## Agent Prompt

For each red team agent, spawn with:

```
You are a red team operator. You have a specific objective to
accomplish against a live target.

TARGET: {TARGET_DESCRIPTION}
ACCESS: {HOW_TO_REACH_THE_TARGET}

OBJECTIVE: {OBJECTIVE}

WIN CONDITION: {WIN_CONDITION}

PLANTED ARTIFACTS: {PLANTED_ARTIFACTS}

You have full whitebox access:
- Source code at {SOURCE_CODE_PATH} — read it to understand the
  system's defenses, find weaknesses, plan your attack
- Live system access — execute your attacks for real
- {DATABASE_ACCESS if applicable}

RULES OF ENGAGEMENT:
In bounds: {IN_BOUNDS}
Out of bounds: {OUT_OF_BOUNDS}

Duration: {DURATION}

HOW TO THINK:

Start by reading the source code and mapping the trust boundaries:
- Where does the system draw the line between trusted and untrusted?
- Where does identity, privilege, or data sensitivity change?
- Where do two components meet and each assumes the other validated?
- What does the system assume is "inside"? Can you get inside?

Then find the seams — the edges between boundaries where transforms
undo validation, where one service trusts another's output, where
new features were added outside the original security model.

Then concentrate force. Pick the weakest seam and push until it
breaks or proves solid. If it cracks, chain — use the first crack
to reach deeper.

DO NOT:
- Run through vulnerability categories like a scanner
- Test every endpoint sequentially
- Spend time on findings that don't advance the objective
- Produce a categorized findings list — write an attack narrative

DO:
- Map boundaries first, attack second
- Focus on the objective — every action gets you closer
- Chain techniques — one weakness enabling access to the next
- Pivot when blocked — understand WHY, then find a different angle
- Document everything — every attempt, response, failure

SCORING:
  Objective achieved with full reproduction:        $50,000
  Partially achieved (proved critical weakness
    in the defense chain):                          $25,000
  Not achieved but identified exact defense that
    stopped you + plausible bypass:                 $10,000

  Claimed achieved but reproduction doesn't work:  -$50,000
  Wasted time on generic scanning instead of
    pursuing the objective:                         -$10,000

REPORT FORMAT:

If you achieve the objective:
  1. OBJECTIVE STATUS: Achieved
  2. BOUNDARY MAP: trust boundaries identified, targeted, and why
  3. ATTACK CHAIN: step-by-step with exact commands and responses
  4. SEAMS EXPLOITED: which boundary transitions failed and why
  5. PROOF: exfiltrated data, unauthorized access, crashed service
  6. RECOMMENDED FIXES: what would have stopped you, in order of
     effectiveness — fix the boundary, not just the symptom
  7. REGRESSION TEST: code that reproduces the attack path for CI

If you don't achieve the objective:
  1. OBJECTIVE STATUS: Not achieved
  2. BOUNDARY MAP: boundaries identified, tested, which held
  3. PATHS ATTEMPTED: each attack path, why it failed, which
     boundary held
  4. DEFENSES THAT HELD: what worked and why — valuable confirmation
  5. CLOSEST APPROACH: nearest to the objective, last boundary standing
  6. WHAT WOULD BE NEEDED: capability, access, or timing to succeed
  7. INCIDENTAL FINDINGS: anything found that's worth fixing
```

## Running Overnight (Instructions for the Human)

For infrastructure targets, the red team runs on an isolated VPS overnight:

```bash
# On the isolated VPS (private/mesh network only)
# Plant test credentials, clear logs, launch:
claude --prompt-file red-team-prompt.md \
       --dangerously-skip-permissions \
       --max-turns 200

# In the morning: read the report
cat red-team-report.md
```

`--dangerously-skip-permissions` is necessary — the agent needs to run arbitrary network commands. This is why isolation is non-negotiable.

`--max-turns 200` gives room for multiple attack paths. The agent burns through turns quickly on dead ends and slows down when it finds something to probe deeper.

## Write Report

Write the report to `.claude/artifacts/redteam/report-{date}.md`.

## After the Assessment

### If objective achieved:

1. **Fix the vulnerability chain** — break any link to prevent the attack
2. **Write regression tests** — the report includes exact reproduction, turn it into a CI test
3. **Update antipatterns** — add the vulnerability class to `.claude/antipatterns.md`
4. **Consider a Hacker Olympics run** — the red team found one path, there may be others

### If objective NOT achieved:

1. **Review defenses that held** — verify they're robust, not coincidental
2. **Review "what would be needed"** — does it match your threat model?
3. **Review incidental findings** — lower-severity issues found along the way
4. **Run with a different objective** — couldn't exfiltrate data? Try crashing the service or escalating privileges.

## Relationship to Other Components

```
Hacker Olympics (static)
  ↓ reads code, reasons about attack paths
  ↓ finds code-level vulnerabilities
  ↓ fixes applied
  ↓
Red Team (live, objective-driven)
  ↓ proves exploitability against running system
  ↓ chains techniques toward specific adversarial goals
  ↓ finds runtime-only issues static analysis misses
  ↓ fixes applied with regression tests
  ↓
Devil's Advocate (periodic)
  ↓ challenges whether the security approach itself is right
```

| | Hacker Olympics | Red Team |
|---|---|---|
| Access | Source code only | Source code + live system |
| Method | Static analysis, hostile code review | Live exploitation toward an objective |
| Lens | "Find vulnerabilities" (categorical) | "Achieve this goal" (adversarial) |
| Agents | 4-6 parallel specialists | 1-3 goal-directed attackers |
| Output | Categorized findings | Attack narrative |
| Finds | Code-level flaws, missing checks | Runtime behavior, integration gaps, defense chain failures |
| Misses | Middleware ordering, deployment config | Deep code issues not in standard execution |

**Recommended sequence:**
1. Hacker Olympics → fix findings
2. Red Team → fix with regression tests
3. Devil's Advocate → challenge the security approach

## Claude Code Feature Integration

### Task Lists
Structure the assessment as an attack narrative:
- Isolation check (verify private IP/localhost)
- Source code analysis (trust boundary mapping, each boundary as sub-task)
- Attack paths identified (ranked by likelihood)
- Each attack path as a task group:
  - Craft payload/technique
  - Execute against live target
  - Result: ✓ succeeded / ✗ blocked (with defense that stopped it)
  - If succeeded: chain to next boundary
- Report generation
- Regression test writing (if objective achieved)

For overnight runs, this task list becomes the attack narrative the user reads in the morning.

### Background Tasks
Run crafted payloads and network probes as background tasks where possible — prepare the next attack path while waiting for the response from the current one.

## Constraints

- **NEVER run against public internet targets.** Isolation is mandatory.
- **NEVER use production credentials or real user data.** Test/sandbox only.
- **Document every attempt.** Failed paths are intelligence.
- **Write an attack narrative, not a findings list.** This is penetration testing, not auditing.
- **All report files inside the project directory.** Never /tmp.
- **Regression tests are mandatory for achieved objectives.** The assessment is not complete without them.
