# 08 reclaim

Free space by removing bytes that provably exist elsewhere - and nothing else.

## Inputs
- the archive, the hash index, and evidence of surviving copies

## Outputs
- deletions, each journalled with its evidence BEFORE the unlink

## Invariants
- deletion goes through the allowlist guard; garbage is a closed list
- a duplicate needs identical content AND a distinct inode
- the journal row is fsynced before the file is removed
- the survivor is re-hashed at the moment of deletion

## Code
| file | role |
|---|---|
| `filearchives/safety.py` | the deletion allowlist, and the version detector that makes a tool refuse |
| `guards/guarded_delete.py` | the only sanctioned delete: proven survivor, different inode, re-hashed now, journalled first |

## Tests
- none yet

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 1 | a path is never grounds to delete | `code:filearchives/safety.py:class Guard` |
| 4 | a surviving copy must be a different inode | `code:guards/guarded_delete.py:same inode` |
| 5 | the filesystem at the instant of the unlink is the only evidence | `code:guards/guarded_delete.py:Re-verified NOW` |
| 6 | the journal is fsynced before the file goes | `code:guards/guarded_delete.py:def _journal` |
