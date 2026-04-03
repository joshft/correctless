# Antipatterns — {PROJECT_NAME}

Every item is a bug class that escaped testing at least once.
The /cspec and /creview skills check new features against this list.

## How to Add an Entry

When a bug is found after merge:
1. Create a new AP-xxx entry (increment the last number)
2. "What went wrong" — describe the bug as a concrete story
3. "How to catch it" — write the spec rule or test that prevents recurrence

## Example

### AP-001: Unvalidated User IDs in Query Parameters
- **What went wrong**: User A accessed User B's data by changing the user ID in the URL. The endpoint checked authentication but not authorization (ownership).
- **How to catch it**: Integration test that calls the endpoint with a valid token for a different user. Assert 403, not 200. Spec rule: "No endpoint returns data for a resource the requester doesn't own."

## Entries

_(none yet — entries are added as bugs are discovered)_
