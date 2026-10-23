# 09 canonical audit

Prove that the finished estate exposes one shallow authority for business,
personal and local repository work. This stage checks navigation and boundaries;
it does not mirror cloud content onto intermittently connected machines.

## Code

| file | role |
|---|---|
| `stages/09_mirror/test_canonical_state.ps1` | check the top of every watched drive against Krish's folder record: recorded folders and never-enter boundaries present, no loose root files, the critical worktree present, and unknown folders reported as waiting on him, without traversing protected boundaries |

## Inputs
- workspace configuration
- accepted user policy
- verified structure receipts

## Outputs
- an independently derived canonical-state report

## Invariants
- protected roots are checked only at their boundary
- expected and unexpected top-level navigation roots are explicit
- a top-level folder outside the layout is Krish's, reported as waiting on him, never an issue to fix
- a missing or disconnected source is unavailable, never empty

## Tests
- canonical-state audit in the completed estate run

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 07 | absent is not empty | `tests/test_powershell_guards.ps1` |
| 09 | long work is resumable | canonical-state report is replaceable and atomic |
