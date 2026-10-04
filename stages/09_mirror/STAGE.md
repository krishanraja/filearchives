# 09 canonical audit

Prove that the finished estate exposes one shallow authority for business,
personal and local repository work. This stage checks navigation and boundaries;
it does not mirror cloud content onto intermittently connected machines.

## Code

| file | role |
|---|---|
| `stages/09_mirror/test_canonical_state.ps1` | inspect only the top-level navigation surfaces, verify every required category and critical worktree, and report unexpected roots without traversing protected boundaries |

## Inputs
- workspace configuration
- accepted user policy
- verified structure receipts

## Outputs
- an independently derived canonical-state report

## Invariants
- protected roots are checked only at their boundary
- expected and unexpected top-level navigation roots are explicit
- a missing or disconnected source is unavailable, never empty

## Tests
- canonical-state audit in the completed estate run

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 07 | absent is not empty | `tests/test_powershell_guards.ps1` |
| 09 | long work is resumable | canonical-state report is replaceable and atomic |
