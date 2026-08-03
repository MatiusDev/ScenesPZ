# The plan, in stages

`docs/PRD-SCENES-RELATIONS.md` says what the mod should feel like. This directory says how
we get there, one completable piece at a time, and `docs/PLAN-STATUS.md` says which piece
is open right now.

## How these are written, and why

**A stage is a thing you can finish.** Not a theme, not an epic. Each has a fixed set of
deliverables, a done criterion you can point at, and one in-game test that proves it. If a
stage cannot be tested in one session on the gaming PC, it is too big and gets split.

**Only the current and next stage are written in detail.** Everything past that is a goal
and a done criterion, nothing more. This is deliberate. Detail written three stages ahead
is fiction — it assumes probe results we do not have and API behaviour we have not checked,
and this project has already paid twice for building on an assumption (`isNPC()`, the decay
maths). A stage gets its detailed file when it becomes next.

**Order is not negotiable where it is marked.** Red Dead Redemption 2's design director is
explicit that the aspiration to give NPCs memory *"led to the creation of the interaction
system that exists for the entire world"* — memory first, the interface second, because the
interface exists to express something already remembered. Building the visible part first
is the tempting mistake and we are not making it.

## The stages

| # | Stage | Goal in one line | Depends on |
|---|---|---|---|
| 00 | [Test world](00-test-world.md) | Somebody to practise on, from the first minute | — |
| 01 | [Durable memory](01-durable-memory.md) | An NPC still knows you after the map unloads | — |
| 02 | [Salience and forgetting](02-salience-and-forgetting.md) | They remember the shooting, not the fifty zombies | 01 |
| 03 | Traits | Two survivors in the same spot react differently, and consistently | 01 |
| 04 | Emotion | Fear and tension that rise from events and settle on their own | 03 |
| 05 | First contact | Your posture is the conversation — gun, aim, speed, distance | 03, 04 |
| 06 | Visible inner state | You can read what they feel without opening anything | 04 |
| 07 | Persuasion | Two or three options the moment offers, floating in the world | 05, 06 |
| 08 | The social graph | They have opinions about each other, and you can disturb them | 02 |
| 09 | Gossip | What one of them believes about you reaches the others, imperfectly | 08 |
| 10 | The settlement | A group that holds a place, divides work, and takes people in | 04, 08 |

## What each of the undetailed stages has to prove

Enough to know it is the right stage, not enough to pretend it is designed.

**03 — Traits.** Every survivor carries fixed dimensions decided at spawn that never
change: how fast fear rises, how close you may come, how readily trust is extended, and
whether persuasion is possible at all. `brain.rnd` gives five stable integers per NPC for
free (`BanditServerSpawner.lua:375`), which is enough to derive them deterministically.
**Done when:** the same NPC makes the same choice twice, and two NPCs in identical
situations do not. The PRD's hard case is the man who cannot be talked to under any
circumstances — some doors are closed, and you find out by trying.

**04 — Emotion.** Emotion changes constantly and decays; memory changes only on events and
never decays. That table in the PRD is the whole design. Whether emotion is *read* from the
engine or *simulated* by us depends on one unrun probe: does the engine tick `getStats()`
for a zombie, or does it sit at defaults forever. **Done when:** an NPC visibly settles
after a threat passes, without the player doing anything.

**05 — First contact.** The mod's one genuinely unusual idea: there is no dialogue box, so
what negotiates is what you do with your body. Bandits already reads exactly these signals
today — `isSprinting`, `isSneaking`, `isAiming`, distance (`ZPCompanion.lua:36-48`).
**Done when:** walking up slowly with the gun down gets a different outcome from jogging up
aiming, reliably, and a frightened NPC that decides to shoot can still miss.

**06 — Visible inner state.** A deep simulation the player cannot read is indistinguishable
from randomness. Gated on the `HaloTextHelper` probe. **Done when:** you can tell an NPC is
about to turn on you before it does, without reading a log or opening a menu.

**07 — Persuasion.** Three inputs, all required: what you do, who you are, and who they
are. Rendered as floating suggestions in the world. **Done when:** the right-click menu is
deleted. Note the tension accepted openly in the PRD — floating suggestions are a menu
drawn in the world, and the discipline is that it must never become a list.

**08 — The social graph.** The brothers example: you did not save one brother and the other
one carries it, permanently. That is not a player→NPC record, it is an edge between two
NPCs that your action disturbed. Nothing in Bandits models it and no PZ NPC mod has built
it. **Done when:** hurting one survivor changes how a second one treats you, because of
their relationship rather than because they saw it.

**09 — Gossip.** Transmission probability, attenuation, and source weight — a rumour must
never hit as hard as a memory. **Done when:** someone you have never met treats you
according to something you did elsewhere, and is sometimes wrong about it.

**10 — The settlement.** The first milestone of the global vision. **Done when:** a group
holds a building, some fight while others get inside, and a stranger can earn a place in it.

## Where the risk actually is

Two answers we do not have can each rewrite several stages, which is the honest reason
stages 03+ stay thin:

- **Does a record survive a cell unload?** If not, stage 01 needs the fuzzy recognition
  fallback in `docs/DESIGN-MEMORY.md` and everything after it slips.
- **Does the engine tick `getStats()` on an NPC?** If it does, half of stage 04 disappears
  and emotion becomes reading rather than simulating.

Both probes ship in the current build. That is why the current test run matters more than
the next feature.
