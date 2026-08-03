# PRD — ScenesRelations

Drafted 2026-08-03 from a design survey with the author. This is the product document: what
the player should feel and why. `docs/NPC-AI-ARCHITECTURE.md` says how it is built,
`docs/CAPABILITY-MAP.md` says what the engine allows, `docs/NPC-BEHAVIOR-PLAN.md` says in
what order.

## Scope

**ScenesRelations is the behaviour and relationship layer.** Nothing else.

A later mod, **Scenes**, will place authored situations in the world — the man running from
zombies whose wife is trapped behind a gate. That example is quoted throughout as an
integration contract, not as scope. If ScenesRelations is right, Scenes becomes a matter of
placing actors; if it is wrong, no amount of authored drama will save it.

## The core bet

**The player's posture is the dialogue.**

There are no dialogue options because there is no dialogue box. What negotiates is what you
do with your body: whether the gun is holstered, whether you are aiming, whether you walk
or run, how close you come, whether you stop when told to.

This is not a limitation worked around. It is the mod's one genuinely unusual idea, and it
is why it can feel like nothing else in Project Zomboid. Almost every game hides
negotiation in a menu because a menu is easier than reading intent from behaviour.

It is also already possible. Bandits reads exactly these signals from the player today
(`ZPCompanion.lua:36-48`): `isSprinting()`, `isSneaking()`, `isAiming()`, and distance.
Verified, in use, no new engine surface required.

## Player-facing pillars

1. **Nobody trusts you on sight.** A stranger in an apocalypse assumes the worst, and is
   usually right. Approaching badly is dangerous.
2. **You earn people by what you do, not by what you pick.** Fighting beside them, giving
   what they need, doing what they ask, and simply not hurting them.
3. **Every survivor is a specific person.** Two NPCs in the same situation react
   differently, consistently, for reasons that belong to them.
4. **They have lives that do not include you.** They fear, they calm down, they hold
   grudges, and they have relationships with each other.
5. **Situations are unrepeatable.** The same encounter twice should not play the same way.

## Emotion and memory are different systems

The clearest structural decision from the survey.

| | Changes | Decays | Examples |
|---|---|---|---|
| **Emotion** | constantly, from events | **yes** | fear, stress, tension, relief |
| **Memory** | only from events | **never** | trust, grudge, debt |

Emotions move the way the player's own do: something happens, they spike, and they settle
when the cause passes. Group events can change several at once — being rescued drops
tension immediately.

Memory does not decay, and time is never a source. This was settled earlier and holds:
decay made *waiting* a strategy, and a mechanic that rewards inaction is not a mechanic.

**The worked example, from the author.** You travel with two brothers and a friend. A
situation forces a choice: save the friend, or save one brother. The rescued NPC's tension
drops and their trust rises. The surviving brother is alive and unharmed — and carries,
permanently, that you did not help his brother.

That example is the specification for three things at once: emotions that respond to
outcomes, memory that does not forgive, and relationships **between NPCs** that your
actions disturb.

## NPC identity

Every survivor carries traits that decide how they read the world. Traits are fixed at
spawn and never change — they are who the person is, not how they feel today.

Traits govern: how fast fear rises, how much proximity is tolerated, how readily trust is
extended, and whether persuasion is possible at all.

**Some people cannot be persuaded.** The author's example: a man who beat his wife before
the outbreak. Approach him however you like; he shoots. This is deliberate and important —
if every encounter is winnable with the right technique, encounters become a puzzle with a
solution, and the tension dies. Some doors are closed, and you find out by trying.

`brain.rnd` already provides five stable integers per NPC at no cost
(`BanditServerSpawner.lua:375`), which is enough to derive traits deterministically.
`brain.personality` is **not** usable — it is flavour only (`alcoholic`, `smoker`,
collectors).

## First contact

The encounter this mod is built around.

1. The NPC notices you and reads your posture: weapon state, aim, speed, distance.
2. It reacts in the world — speech and floating text. "Don't come closer." "Put it down."
3. You answer with behaviour, or with a floating suggestion offered at that moment.
4. It escalates or relaxes based on its fear, its weapon, whether it is alone, and its
   traits.
5. If it goes wrong, it shoots — and can miss.

**Failure is probabilistic, not scripted.** A frightened NPC with a rifle who decides to
fire may still miss. That single detail keeps a bad approach from being a death sentence
and keeps a good one from being a guarantee.

Being outnumbered lowers their trust on its own. Three armed strangers walking up is a
different event from one.

## Persuasion

Three inputs, all required:

- **What you do** — posture, distance, compliance, gifts, and your history with this
  person.
- **Who you are** — your record. Someone who has hurt survivors before is approaching with
  that behind them.
- **Who they are** — their traits and their current fear.

Persuasion appears as **floating suggestions in the world**, not a dialogue panel. The
player picks from what the moment offers, and the moment is generated from the three inputs
above.

Note the tension deliberately accepted here: the player asked for no menus, and floating
suggestions are a menu rendered in the world. That is the right compromise — the
information stays diegetic and the interaction stays fast — but it must never become a
list. Two or three options at most, drawn from the situation.

## Explicitly out of scope

- **Dialogue trees.** Content treadmill. The whole point is that behaviour is the language.
- **Authored quests.** That is Scenes.
- **A charisma stat.** Project Zomboid has none, and inventing one moves the skill from the
  player to the character sheet. What you do is what persuades.
- **Faction reputation tables.** Relationships are per person. That is the thing this mod
  exists to replace.

## What must be verified before building

Every one of these is a prerequisite, not a detail. Guessing any of them is how this
project has already lost sessions.

| Question | Blocks | Status |
|---|---|---|
| Does the engine tick `getStats()` on a zombie? | whether emotions are read or simulated | probe written, unrun |
| Does `HaloTextHelper` accept an `IsoZombie`? | every floating indicator in this document | not probed |
| Can we read the player's equipped weapon and aim state reliably? | the entire posture system | `isAiming` verified; weapon-in-hand not |
| Can an NPC approach the player unprompted? | NPC-initiated contact | not investigated |
| Can we trigger animations on an NPC? | body language as a channel | not investigated |

## Open questions

- **How does the player perceive an NPC's inner state?** Answered partially — floating
  text and speech. Body language remains attractive and unverified. The risk stands: a deep
  simulation the player cannot read is indistinguishable from randomness.
- **What is an NPC-to-NPC relationship, mechanically?** The brothers example demands it and
  nothing in Bandits models it. Needs its own design pass.
- **How much unpredictability is too much?** "Unrepeatable situations" and "learnable
  rules" pull against each other. The player must be able to get better at approaching
  people, or the system reads as arbitrary.
