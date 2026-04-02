Triage and resolve GitHub Copilot's PR review comments for the current branch.

## Step 1 — Identify the PR

Determine the current branch and find its open PR using `gh pr view --json number,url,headRefName`. If no PR exists, stop and tell the user.

## Step 2 — Fetch all Copilot review comments

Use the GitHub MCP `pull_request_read` tool (or `gh api`) to retrieve all review comments on the PR. Filter to only comments authored by `copilot` (GitHub's Copilot reviewer bot).

**Skip these comments entirely — do not validate or present them:**

- Comments whose thread is already **resolved**
- Comments marked as **outdated** (the underlying code has changed since the comment was made)

Only proceed with open, active, non-outdated comments.

Print a numbered summary table of the remaining comments:
| # | File | Line(s) | Copilot's claim (one-line summary) |

If zero comments remain after filtering, report that and stop.

## Step 3 — Validate each comment via subagent consensus

For **each** open Copilot comment, you **must** launch at least 2 subagents using the `Agent` tool to independently validate the claim. Do not validate comments yourself — every comment needs multi-agent consensus.

**Selecting subagent types:** For each finding, review the `subagent_type` options available on the Agent tool. Launch **2 subagents** by default, picking agents that bring different perspectives on the concern. Add a **3rd subagent** only if the finding spans multiple specialties (e.g., a correctness issue with security implications). **Never exceed 3 subagents per finding.** If no specialized agents are a clear fit, fall back to whichever general-purpose code review agents are available.

**Each subagent prompt must include:**

1. The full text of Copilot's comment (verbatim).
2. The file path and line number(s).
3. Instruction to read the relevant file and **surrounding context** (not just the diff hunk — enough to understand the code's intent).
4. Instruction to render a verdict: **valid**, **partially valid**, or **false positive**.
5. If valid/partially valid: draft one or more concrete fixes (as code blocks) with a clear explanation of impact.
6. If false positive: explain specifically why Copilot is wrong.

**Consensus rule:** A finding is valid only if **both** (or a majority of) subagents agree it is valid or partially valid. If they disagree, present the disagreement to the user and let them decide.

**Launch all subagents in parallel** — emit all Agent tool calls in a single message (both agents for finding #1, both for #2, etc., all at once). Do not serialize them.

## Step 4 — Present findings to the user one at a time

**Critical: Do NOT present all findings at once.** Show exactly ONE finding per message using the `AskUserQuestion` tool's interactive UI, wait for the user's response, then show the next.

Once all validations complete, first print a **one-line scoreboard**:

```
Copilot review: N findings (V valid, F false positives)
```

Then iterate through findings sequentially — valid findings first, then false positives.

### For each valid finding

Print a short context block:

```
[N/TOTAL] path/to/file.ext:L42  (valid | partially valid)

> Copilot's original comment (verbatim, do not truncate)

Assessment: subagent explanation of why this is valid and actual impact.
```

Then use `AskUserQuestion` with **two questions in a single call**:

**Question 1 — Action** (single-select with previews):
- `header`: `"Action"`
- `question`: `"[N/TOTAL] How do you want to handle this finding in path/to/file.ext:L42?"`
- `options` (use `preview` on each fix to show the code diff):
  - label: `"Apply fix 1 (Recommended)"`, description: one-line summary, `preview`: code block showing the change
  - label: `"Apply fix 2"` (if exists), description: summary, `preview`: its code block
  - label: `"Apply fix 3"` (if exists), description: summary, `preview`: its code block
  - label: `"Skip"`, description: `"Leave comment open, do not apply any fix"`
- The built-in "Other" option lets the user type completely custom fix instructions.

**Question 2 — Feedback** (single-select):
- `header`: `"Feedback"`
- `question`: `"Any notes or feedback on this finding?"`
- `options`:
  - label: `"No notes"`, description: `"Proceed with the selected action as-is"`
  - label: `"Modify before applying"`, description: `"I'll describe changes to make to the selected fix"`
- If the user selects "Modify before applying" or uses "Other", read their instructions and adjust the fix accordingly before applying.

This renders as a tabbed wizard: the user tabs between questions, with the Action tab showing a side-by-side preview of each fix option.

### For each false positive

Print a short context block:

```
[N/TOTAL] path/to/file.ext:L42  (false positive)

> Copilot's original comment (verbatim)

Dismissed: subagent reasoning for why this is a false positive.
```

Then use `AskUserQuestion` with **two questions in a single call**:

**Question 1 — Action** (single-select):
- `header`: `"Action"`
- `question`: `"[N/TOTAL] This was assessed as a false positive. What do you want to do?"`
- `options`:
  - label: `"Dismiss"`, description: `"Resolve the comment on GitHub — Copilot was wrong"`
  - label: `"Reopen"`, description: `"Actually valid — treat as a real finding to fix"`
  - label: `"Skip"`, description: `"Leave comment open, decide later"`

**Question 2 — Feedback** (single-select):
- `header`: `"Feedback"`
- `question`: `"Any notes on this dismissal?"`
- `options`:
  - label: `"No notes"`, description: `"Proceed with the selected action"`
  - label: `"Add context"`, description: `"I want to explain why I agree/disagree"`
- If the user provides notes via "Add context" or "Other", record them for the GitHub resolution comment.

### Rules

- **One finding at a time.** Do not print the next finding until the current `AskUserQuestion` is answered.
- After the user responds, apply their choice, print a one-line confirmation (e.g., `Applied fix 1 to file.ext:L42`), then immediately show the next finding.
- If the user selects "Reopen" on a false positive, present it again as a valid finding with fix options.
- If the user selects "Other", read their custom instructions and apply accordingly.
- After the last finding, proceed to Step 5.

## Step 5 — Resolve comments on GitHub

After all findings have been addressed:

1. For every comment where a fix was **applied**: resolve the comment thread on GitHub using `gh api` or the GitHub MCP tools.
2. For every **false positive**: resolve the comment thread as well (the claim was reviewed and dismissed).
3. For **skipped** comments: leave them open.

Report final counts: `X resolved (Y fixed, Z dismissed) · W left open`

## Constraints

- Never auto-apply fixes without user confirmation.
- Never resolve a comment without either applying a fix or explicitly dismissing it as a false positive.
- If a Copilot comment references multiple issues, treat each issue as a separate finding.
- If the subagent is uncertain, err on the side of calling it valid and letting the user decide.
