# 03 dating

Give every document a date, from the best signal available.

## Inputs
- the inventory, and the documents themselves

## Outputs
- a date per file, with the SOURCE of that date recorded beside it

## Invariants
- the source of a date is always recorded; a guess is never silent
- filename, then folder, then document text - in that order of trust
- an undated file stays undated rather than receiving an invented date

## Code
| file | role |
|---|---|
| `stages/03_dating/date_from_signals.py` | filename patterns, then the folder name, then the document's own text |

## Tests
- none yet

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 13 | no EXIF exists, so the folder name is the date of last resort and is recorded as such | prose-only |
