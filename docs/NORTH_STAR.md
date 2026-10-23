# North Star

Status: Current
Owner: Krish Raja
Last verified: 2026-10-18

> Like Control Center, filearchives' job never ends: as every other repository sprawls and becomes more ambitious, it keeps Krish's files clean and where he wants them, which gets harder every month.
>
> It never moves or removes a folder Krish made without asking first. It asks what goes in a new folder, then keeps it clean every week.

Set by Krish on 18 October 2026 and rewritten by him on 23 October 2026. It is not reached yet. It is what every session in this repository works toward.

## The number

**Folders moved or removed without Krish's OK, per week**: 0 by 26 October 2026, on a countdown weekly ladder. Zero every week from 26 October 2026, and a cleanliness check completed every 7 days. Its job never ends: as every other repository sprawls, it keeps Krish's files clean and where he wants them.

```yaml north-star-metric
metric: "Folders moved or removed without Krish's OK, per week"
unit: count
direction: down
target: 0
deadline: 2026-10-26
ladder_shape: countdown
source: "The engine's own run log"
status: active
ladder:
  - [2026-10-26, 0]
```

Urgency (U1 to U5) is worked out every week from where the number stands against that week's target, by [the harness contract](https://github.com/krishanraja/ai-harness/blob/main/contract/north-star-metric.md). Set by Krish on 23 October 2026.

## How to use it

- Read it before any work, every session.
- Before you start, say which part of it the task moves. If the task moves nothing toward it, say so first and let Krish decide.
- Prefer the work that moves it furthest, and close each session by noting what moved.
- Only Krish changes this file. Record his ruling in the commit body as `Ruling (Krish, YYYY-MM-DD): ...`.
- When it is reached, say so and ask Krish for the next one.
