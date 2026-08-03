# Design — memory and the social graph

Drafted 2026-08-03 after research into how other games and agent systems do this. The
subsystem the PRD depends on and nothing in Project Zomboid provides.

## The problem, stated precisely

Three questions that look like one:

1. **Persistence.** You fight beside Theodore for half an hour. You walk eight blocks away
   and his area unloads. You come back. Does he know you?
2. **Growth.** Over a hundred-hour playthrough you meet hundreds of survivors. If every
   encounter is remembered forever, the save file and the per-tick cost grow without bound.
3. **Relationships between NPCs.** The brothers example: you did not save one brother, and
   the other one carries it. That is not a player→NPC record. It is an edge between two
   NPCs that your action disturbed.

A single trust number solves none of them.

## What the field does

Researched 2026-08-03. Four findings that transfer.

**Memory is tiered, not flat.** Believable-agent architectures separate raw timestamped
episodes from consolidated higher-level conclusions. Episodes are cheap to write and
expensive to keep; conclusions are the opposite.

**Consolidation is the load-bearing part.** In the 25-agent Generative Agents study,
removing the reflection step — the one that synthesises episodes into insights — made
emergent coordination disappear entirely. Agents that only accumulate events do not
develop opinions.

**Forgetting is a feature, not a budget compromise.** A memory model that lets an agent
forget or hold hazy memories is what produces human-like variability in how it understands
the world. This matters here: we need forgetting for cost reasons anyway, and the research
says designing it well makes NPCs *more* believable rather than less.

**Reputation spreads along a graph, with a probability.** Propagation speed depends on
graph degree and diameter, and information originating in dense hubs travels faster than
information from the edges. Realism comes from a per-transfer transmission probability
rather than perfect knowledge sharing — NPCs pass on what they heard, imperfectly.

Sources:
[Parameterized memory model for NPC AI](https://cs.gmu.edu/~gaia/IntellAgents/IVA2013-memory-final.pdf) ·
[Player reputation via belief formation in NPC societies](https://www.sciencedirect.com/science/article/abs/pii/S1875952123000204) ·
[Reputation systems for NPC interactions (AAAI)](https://cdn.aaai.org/ojs/12950/12950-52-16467-1-2-20201228.pdf) ·
[Episodic memory for agents](https://atlan.com/know/episodic-memory-ai-agents/)

## What survives contact with Project Zomboid

The research assumes infrastructure we do not have. What has to be cut and why:

| Technique | Verdict here |
|---|---|
| Retrieval by semantic relevance | **Cut.** Requires embeddings. This is Kahlua, Lua 5.1, running while the game renders. |
| Retrieval by recency and salience | **Keep.** Both are integers. Cheap. |
| Episodic → consolidated tiering | **Keep.** It is the answer to unbounded growth. |
| Reflection producing natural-language insight | **Adapt.** No language model. Consolidation produces a *label* and a number, not a sentence. |
| Dense relationship graph | **Cut.** N² edges over hundreds of survivors is not affordable. |
| Sparse graph, edges created on contact | **Keep.** Most survivors never meet each other. |
| Gossip with transmission probability | **Keep.** Cheap, and it is exactly the brothers example. |

## The proposed design

Three layers. Each is allowed to forget the one below it.

### Layer 1 — episodes

What happened, timestamped, bounded. Roughly what `record.memory` already is.

```
{ day = 12, delta = -25, kind = "attacked", salience = 3 }
```

Kept: the most salient N, not the most recent N. That single change is what makes an NPC
remember the day you shot their friend and forget the fifty zombies you killed together.
Being shot at is salient; a good afternoon is not.

### Layer 2 — the conclusion

When episodes are dropped, they leave a mark instead of vanishing. Consolidation runs when
the episode list is full: the dropped entries are folded into a small set of durable
labels with weights.

```
{ dangerous = 4, generous = 1 }
```

This is the layer that survives forever, and it is tiny — a handful of integers per person
you have actually met. It is also what makes an NPC able to have an *opinion* rather than a
transcript. The research is blunt that removing this step is what killed emergent behaviour
elsewhere.

### Layer 3 — the edge

The current state of one relationship: trust, grudge, and when it was last touched.

Edges exist only between people who have actually interacted. The player has an edge to
everyone they have met; NPCs have edges only to those they have co-witnessed something
with. That keeps the graph sparse by construction rather than by pruning.

## Storage

Not on the entity. The entity dies when the cell unloads, which is the whole problem.

Bandits already solved this in this exact codebase: 32 sharded ModData tables,
`BanditC0`..`BanditC31`, keyed by `id % 32`. Sharding keeps any single table small enough
to serialise cheaply. We copy the pattern with our own prefix — never writing into theirs.

**Identity, and the fallback if it fails.** Recognition needs the same NPC to return under
the same id. If the probe shows it does not, there is a second path worth designing rather
than giving up on: recognise the way people actually do, by **name plus traits plus clan**.
A fuzzy match is wrong occasionally, and being occasionally wrong about whether this is the
person who robbed you is arguably more human than a database key. That is a fallback, not
a preference — but it means a failed probe does not kill the premise.

## Gossip

The mechanism the brothers example needs.

When two NPCs are close and calm, one may pass on what it believes about the player. Three
parameters, all from the research:

- **Transmission probability.** Not everything is repeated. This is what stops the whole
  map knowing your name within an hour.
- **Attenuation.** Second-hand belief is weaker than what you saw yourself. A rumour should
  never hit as hard as a memory.
- **Source weight.** What a trusted friend says outweighs what a stranger says.

The research warns about hub effects: information starting in a dense group spreads far
faster than information from the edges. Here that is a feature — hurting someone inside an
established camp should have consequences that reach further than hurting a loner.

## What is genuinely new here

Not in any Project Zomboid mod, and worth stating so it is built deliberately:

- **NPCs holding opinions about each other**, changed by what the player does to a third
  party. Every existing NPC mod models only player→NPC.
- **Salience-based forgetting** rather than a fixed-size ring buffer.
- **Consolidation into traits.** An NPC that has forgotten the incident but not the
  conclusion.
- **Imperfect gossip.** Belief that is wrong because it was passed along badly.

## Cost budget

Stated up front, because "it got slow" is discovered too late otherwise.

- One record per NPC the player has **met**, not per NPC spawned.
- Episodes capped per relationship. Currently 12; salience-ranked rather than FIFO.
- Consolidated labels: a handful of integers, permanent, negligible.
- NPC↔NPC edges created only on co-witnessed events.
- Gossip evaluated on a slow tick, never per frame, and only for NPCs already in the
  proximity cache Bandits maintains.

`BanditUtils.AreEnemies` already runs 460,361 times per minute in this game. Anything we
add on a per-frame path is a mistake by default.

## Must be probed before building

1. **Does a record in our own sharded ModData survive a cell unload and a save/reload?**
   Blocks everything above.
2. **Is the NPC id stable across that same cycle?** Decides whether the fallback
   recognition design is needed.
3. **What day is it, cheaply?** Episodes are timestamped; there must be a game-day source
   that does not cost anything to read.

## Phasing

1. Move the existing trust record off the entity into a sharded store. No new features —
   same behaviour, durable. Prove it with the probe.
2. Salience ranking on the existing episode list.
3. Consolidation into labels when episodes are dropped.
4. NPC↔NPC edges on co-witnessed events.
5. Gossip.

Steps 1 and 2 are small and make everything after them possible. Nothing past 3 should be
designed in detail until 1 is confirmed working in a real save.
