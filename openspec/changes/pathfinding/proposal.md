# Proposal: Strategic Pathfinding

## Intent

NPCs walk the shortest line through obstacles and rely on a watchdog to unstuck them.
Telemetry proves this is wrong: 10 of 20 recent jams were `solid` (map walls), 6 `clear`
(the obstacle was not on the straight line at all). The watchdogs clears the queue, the
sweep re-queues the same destination, and the NPC walks back into the same wall. We need a
decision layer that evaluates obstacles BEFORE the first step and chooses climb/smash vs
go-around, leaving the engine pathfinder to execute the chosen route.

## Scope

### In Scope

- **RouteDecision**: a pure query that takes destination + WhatBlocks result and returns
  crossing point (route through opening) or walk-around waypoint
- **Wire into GoAndDo/assertFollow**: when a direct line is blocked, choose a route instead
  of walking into the obstacle
- **Instrumentation**: log every route decision (chosen vs rejected alternatives) so the
  next play session produces verifiable data

### Out of Scope

- Route memory / caching across sweeps (future, after the single-route case works)
- Multi-hop routes (building shell → cross → building interior)
- Cost comparison of multiple candidate openings (FindOpening already ranks by tier+dist)
- Breaking doors/windows as a planned action (escape hatch: the watchdog still does this)
- Changing engine pathfinder behavior (we do not touch `pathToLocation`)

## Capabilities

### New Capabilities

- `route-decision`: evaluates whether a direct-line move is blocked by a passable obstacle
  and chooses between crossing at an opening vs walking around

### Modified Capabilities

None — this is net-new behavior, not a requirement change.

## Approach

Add `Move.ChooseRoute(zombie, tx, ty, tz)` — a pure query between destination selection
and GoAndDo. When `WhatBlocks` reports an obstacle the NPC CAN act on (door, window, hop,
tall), and `FindOpening` finds a viable crossing point, ChooseRoute returns that opening as
the intermediate waypoint. GoAndDo walks to the opening first; Bandits' bump handler does
the crossing on arrival. When the obstacle is `solid` or `locked` with no alternative,
walking around (engine default) is the fallback.

The call chain becomes:
```
caller → WhatBlocks → blocked? → ChooseRoute → opening? → GoAndDo(opening) → bump cross
                                    ↓ no
                               GoAndDo(destination) → engine pathfinder
```

Watchdog stays as safety net for everything this layer misses (zombie shoves, world
mutations mid-walk). No new task actions, no engine surface, no state outside the sweep.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `client/ScenesRelationsMove.lua` | Modified | Add ChooseRoute, wire into GoAndDo |
| `client/ScenesRelationsAutonomy.lua` | Modified | Wire assertFollow through ChooseRoute |
| `client/ScenesRelationsLoot.lua` | Modified | Pass destination through ChooseRoute |
| `client/ScenesRelationsIdle.lua` | Modified | Pass destination through ChooseRoute |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| climbOverFence/Wall may not work on IsoZombie | Medium | pcall + log; watchdog catches the fallback |
| ChooseRoute cost per sweep (WhatBlocks + FindOpening) | Low | Gated on WhatBlocks returning an obstacle; most sweeps are clear |
| No route memory → NPC could oscillate between two openings | Medium | Tier ordering favors the nearest; oscillation logged and investigated before building memory |
| FindOpening returns `break` tier which we do not act on | Low | ChooseRoute treats `break` as no route; watchdog handles it |

## Rollback Plan

ChooseRoute is a pure query — nothing it returns is cached or persisted. Removing the call
site in GoAndDo reverts to today's behavior: engine pathfinder runs uncorrected, watchdog
unsticks. No data migration, no save format change.

## Dependencies

- `Move.WhatBlocks` (exists, verified)
- `Move.FindOpening` (exists, verified)
- `BanditUtils.GetAccessSquare` (upstream, exists)
- `LosUtil.lineClearCollide` (vanilla, exists)
- Bandits bump handler for window/door crossing (upstream, exists)

## Success Criteria

- [ ] NPC reaches a destination behind a door by walking to the door instead of hugging the wall
- [ ] NPC crosses a fence when a fence stands between it and a nearby target
- [ ] NPC still reaches destinations with no opening (walks around via engine pathfinder)
- [ ] Watchdog still fires as safety net for cases ChooseRoute does not handle
- [ ] Log contains a route-decision line per blocked walk, naming the obstacle and the chosen action
