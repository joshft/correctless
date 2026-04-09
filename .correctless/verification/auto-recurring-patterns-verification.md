# Verification: Auto-Promote Recurring Antipatterns to Architecture

## Rule Coverage
| Rule | Test(s) | Status | Notes |
|------|---------|--------|-------|
| INV-001 | INV-001a-e (5 tests) | covered | frequency, promotion, cap of 2, ARCHITECTURE ref, defer |
| INV-002a | INV-002a-a,b,c (3 tests) | covered | frequency, promotion, creation/update tie |
| INV-002b | INV-002b-a (1 test) | covered | threshold crossing language |
| INV-003 | INV-003a-h (8 tests) | covered | Guards against, How to catch it, What went wrong, PAT/ABS structure — both files |
| INV-004 | INV-004a,b (2 tests) | covered | deduplication via ARCHITECTURE.md AP-xxx search — both files |
| INV-005 | INV-005a-j (10 tests) | covered | Add/Skip/Modify/Defer + escape hatch — both files |
| INV-006 | INV-006a-f (6 tests) | covered | threshold=3, graceful skip, "N findings across M features" format — both files |
| INV-007 | INV-007a,b (2 tests) | covered | regardless of relevance, separate concern |
| INV-008 | INV-008a (1 test) | covered | exact match Write(.correctless/ARCHITECTURE.md) in frontmatter |
| PRH-001 | PRH-001a,b (2 tests) | covered | human approval gate — both files |
| PRH-002 | PRH-002a-f (6 tests) | covered | negative assertions on both config templates |

**Coverage: 11/11 rules covered, 46 tests total, 0 uncovered, 0 weak**

## Dependencies
- No new dependencies (shell/markdown-only feature)

## Architecture Compliance
- ✓ All ARCHITECTURE.md references use `.correctless/ARCHITECTURE.md` (R-008)
- ✓ Structured decision format matches existing conventions (INV-005)
- ✓ sync.sh --check passes (no distribution drift)
- ✓ New test file wired in CI and commands.test
- ✓ cpostmortem frontmatter has Write permission for .correctless/ARCHITECTURE.md

## QA Class Fixes Verified
- QA-001 (INV-004): cpostmortem deduplication now specifies "literal AP-xxx string" search ✓
- QA-002 (INV-003): Both skill files now include Test field in draft skeleton ✓
- QA-003 (INV-001): Cap instruction strengthened with "After the 2nd suggestion, stop" ✓

## Smells
- None found

## Drift
- None found

## Spec Updates
- No spec updates during TDD

## Overall: PASS with 0 findings
