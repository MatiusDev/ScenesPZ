# NPC AI architecture

Written 2026-08-03. The whole shape of what we are building, above the staged execution
plan in `docs/NPC-BEHAVIOR-PLAN.md`. That file says what to build next; this one says what
it is part of, so that a decision made in stage 3 does not have to be undone in stage 7.

## The premise

**Bandits gives us the body. We are building the mind.**

That is not a slogan, it is an accurate description of the split:

- Their **programs** are reflexes. `ZPBandit.Main` asks "is there a target?" and either
  walks at it or shrugs. Nothing is weighed against anything else.
- Their **task queue** is a motor system, and a good one. 49 verified verbs, animation
  handling, multiplayer sync. There is no reason to rebuild any of it.
- What is missing is **everything between "something is nearby" and "perform this verb"**.
  An NPC has no wants, no appraisal of its own situation, and no way for two of them to
  reach different conclusions from the same facts.

Everything below is that middle.

## The layers

| Layer | The question it answers | Today | Owner |
|---|---|---|---|
| **Needs** | What do I want, absent anything happening? | nothing | ours |
| **Perception** | What can I know right now? | caches only | shared |
| **Appraisal** | What does that mean for me? | one slice | ours |
| **Decision** | Given everything, what do I do? | a single `if` | ours |
| **Execution** | How do I physically do it? | complete | Bandits |
| **Memory** | What do I carry forward? | trust + last 12 events | ours |
| **Social** | How do others change my mind? | direct witness only | ours |

Read that table as a work queue. Execution is done and is not ours. Everything above it is
roughly empty, and the emptiest layer — Needs — is the one that decides whether any of the
rest can feel alive.

## The two seams, and when to graduate

Verified: programs are dispatched by name from a plain global table,
`ZombiePrograms[program.name][program.stage](bandit)` (`BanditUpdate.lua:1894`). So both
of these are additive and neither replaces Bandits code.

**Seam A — push a task.** `Bandit.AddTaskFirst(zombie, task)`. Interrupts whatever the
program queued. This is what `ScenesRelationsThreat.lua` uses.

- Right for: reactions. One thing, now, then back to normal.
- Wrong for: goals. Their program refills the queue the moment it drains, so anything
  needing more than a few seconds gets overwritten by a shrug.

**Seam B — register a program.** `ZombiePrograms.ScenesSurvivor = { Prepare = ..., Main =
... }` and `Bandit.SetProgram(zombie, "ScenesSurvivor", {})`. Ours end to end, running on
their update loop, with their task queue underneath.

- Right for: anything with a goal that outlives one queue drain.
- Cost: we own that NPC's behaviour completely while it runs, including making sure it
  hands back cleanly.

**The rule:** a behaviour that must survive more than one queue drain belongs in a program,
not a task. We are at the edge of that now — shelter-seeking already half-breaks under
seam A, which is why test 7 warns that an NPC may wander off after reaching the window.

## Needs

The layer that does not exist, and the one the vision depends on.

**Why they matter more than they look.** A need is the only thing that makes an NPC want
something when the player is not doing anything. Without needs, every behaviour is a
response to the player, and an NPC that only responds is a vending machine with legs. With
needs, an NPC has a reason to be somewhere at 3am, and the player walking in on that is
where the world starts to feel inhabited.

**The open question.** Does an NPC own the player's systems — thirst, hunger, panic — or
only look like it does? Evidence so far, all indirect:

- Every `getStats()` / `getBodyDamage()` / `getMoodles()` call in Bandits is on a *player*
  variable. Not one is on their own NPCs.
- `Bandit.UpdateEndurance` (`Bandit.lua:423`) reimplements endurance as `brain.endurance`
  rather than calling the engine's stat. You do not reimplement a system that works.
- The brain carries exactly five need-like fields: `endurance`, `health`, `infection`,
  `sleep`, `speech`. No hunger, no thirst, no panic.

That is strong, and it is still inference. The probe added to `ScenesRelationsRun.lua`
settles it: it calls all three inside `pcall` and logs whether they exist. **Design nothing
here until that line is in a log.**

**If the answer is no** — the likely case — needs are ours, stored on the brain, ticked
once per in-game minute. Three floats and a decay rate is not expensive. What is expensive
is pretending an NPC has the player's full simulation; it does not need one to be
convincing.

**The design rule that keeps this honest:** a need must be able to *lose*. Thirst that
always wins is a script with extra steps. The interesting behaviour is the survivor who
stays thirsty because leaving cover is worse, and the one who does not and gets bitten.

## Decision: from ifs to weighing

Today the entire decision layer is one line:

```lua
if outnumbered and not isBrave(brain) then posture = "flee" end
```

That is correct for one axis and collapses at three. The shape it has to become: every
candidate goal scores itself from needs and perception, the best score wins, and the winner
has to beat the current goal by a margin so nobody oscillates in a doorway.

Two constraints from this codebase specifically:

- **Keep it a table of small functions**, one per goal, each returning a number. No class
  hierarchy — this runs in Kahlua on a machine also rendering a game.
- **Every score must be loggable.** The only debugger here is `console.txt`. If we cannot
  print why an NPC chose to flee, we cannot fix it, and that has already cost this project
  two sessions.

## Social

Trust currently moves only from what an NPC personally witnessed. The vision needs more:

- **Propagation.** What one saw, the group learns. `brain.clan` and the proximity cache
  already exist; this needs no new engine surface.
- **Influence.** A calm NPC near a panicking one should lower its fear. This is the
  concrete form of "que entre ellos mismos busquen calmarse", and it needs fear to be a
  persisting number first — which is a Needs-layer dependency, not a social one.
- **Roles.** Someone the others follow. The settlement needs this; nothing before it does.

## What "alive" means

Acceptance tests for the whole project, not for a stage. If these are true we succeeded,
whatever the code looks like.

1. Two NPCs in the same situation do different things, and you can name the reason.
2. An NPC does something you did not ask for and it makes sense in hindsight.
3. An NPC refuses you and you understand why without reading a log.
4. Leaving them alone for a day changes something.
5. **You feel bad when one dies.**

The fifth one is the real target. Everything above it is machinery for producing it.

## Out of scope, permanently

Naming these now so they stop coming back as good ideas at midnight.

- **Full survival parity with the player.** An NPC does not need a nutrition system to read
  as hungry.
- **Dialogue trees.** Content treadmill. Dialogue happens when there is something worth
  saying — see the plan.
- **Faction reputation tables.** Relationships are per person. A table of numbers per
  faction is the thing this mod exists to replace.
- **Pathfinding.** The engine's job. If an NPC gets stuck on a fence, that is not our
  layer.

## Order of attack

1. **Answer the needs question.** One log line. Blocks the entire Needs layer.
2. **Finish the current slice.** Threat response has to survive `docs/TEST-RUNS.md` before
   anything is built on it.
3. **Graduate to seam B.** Our own program, so goals outlive a queue drain.
4. **Needs, minimal.** Two or three, with decay, visible in the debug label.
5. **Decision by weighing.** Once there is more than one thing to weigh.
6. **Social influence.** Once fear persists.
7. **Settlement.** Once NPCs have goals that survive the player logging off.

Steps 1 and 2 are next. Everything after 3 is design that should be revisited with real
data, not planned in detail now.
