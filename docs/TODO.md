# TODO — noticed in play, not scheduled yet

Things spotted during testing that are real but belong to no open stage. Each one gets a
line here rather than derailing whatever is being built. Nothing is picked up from this
list until a stage claims it.

---

## Bandits do not reanimate

**Seen:** an NPC killed by a bite stays dead. It should stand back up after whatever delay
the sandbox is configured for, exactly as a player corpse does.

**What is already known:** Bandits has the machinery. `ZAZombify` is a task action, and
`BanditUpdate.lua` queues `{action="Zombify", anim="Faint", lock=true, time=200}` when
`brain.infection >= 100`. So turning exists, and it is driven by their own infection model
rather than by the vanilla reanimation timer.

**The question to answer first:** does an NPC killed outright by a zombie ever accumulate
infection, or does infection only rise on a bite that was survived? If the latter, the fix
is a death hook, not a tuning change.

**Why it matters:** a survivor who dies and stays a corpse is a prop. One who gets up is a
consequence, and it is what makes losing somebody land.

---

## Corpses do not hold a horde

**Seen:** zombies bite an NPC, kill it, and immediately switch to the player. Nobody stays
to feed.

**Wanted:** some of the horde stays on the body -- as many as fit, or up to a cap around
30 -- with their attention on the corpse. The rest come for the player.

**Why it matters, in the author's words:** sacrificing an NPC to a horde should work. Right
now killing one buys nothing, because the whole horde arrives anyway. That is a tactic the
game appears to offer and does not.

**What to check first:** whether vanilla has a feeding-on-a-corpse state at all, or whether
the distraction has to be built from a target override. `brain.eatBody` exists on the
Bandits brain, which hints the state exists for NPCs eating bodies -- worth reading before
designing anything.

---

## Two systems both decide posture

**Seen in the code, not in play.** `ScenesRelationsThreat.lua` decides fight-or-flee on its
own sweep, and `ScenesRelationsAutonomy.lua` decides a priority rung on another. That is
two places owning one rule, which is what rule R6 in `docs/CODE-REVIEW-RULES.md` exists to
stop, and it is how the talk cooldown already drifted once.

**The intended end state:** autonomy owns the decision and threat becomes the executor it
calls for the shelter behaviour. Deliberately not done in the same pass that introduced the
ladder, so that if the ladder is wrong there is one thing to revert rather than two.
