# Test runs

Written 2026-08-03. What to do on the gaming PC and what counts as a pass.

Run them in order. Each one depends on the previous passing — if test 3 fails, tests 4-9
tell you nothing, so stop and report rather than pushing through. Every session on that
machine is expensive; a clean "test 3 failed, here is the log" is worth more than a full
run of noise.

All log lines land in `C:\Users\<user>\Zomboid\console.txt`. Ours are prefixed `SREL|`.

## Setup, once

1. Run `tools/sync-mods.sh` on the Arch box.
2. In Steam → Project Zomboid → Properties → Launch Options: `-debug`.
3. In the in-game mod list enable **`Bandits2`**, **`scenesRelations`**, **`tlouFactions`**,
   **`scenesDoctor`**. Week One and The Ark stay **off**.
4. Load a save. Right-click the ground → **Spawn Bandit Clan → TLOU_Survivors**.
   Six non-hostile survivors appear.

If the submenu is empty, `tlouFactions` is not enabled — nothing else will work.

---

## 1. Trust falls when you attack — regression

Already passed on 2026-08-03. Re-run it because everything else builds on it.

**Do:** hit one survivor twice while another watches from within 12 tiles.

**Pass:**
```
SREL| <id>: -25 (attacked) -> trust -25 [wary]
SREL| <id>: -25 (attacked) -> trust -50 [hostile]
SREL| <id>: -10 (saw attack) -> trust -10 [neutral]
```
The one you hit turns on you at the second blow.

**Fail means:** a Lua error in `ScenesRelationsEvents.lua`. Send the stack trace.

---

## 2. Trust rises when you fight beside them — new

**Do:** stand near a survivor with no history and kill zombies within its sight. Keep
going for a couple of minutes.

**Pass:** the trust line climbs and eventually crosses a tier:
```
SREL| <id>: +2 (fought beside) -> trust 25 [friendly]
SREL| 1 gained ground for fighting beside the player
```

**Note:** only tier crossings print. Silence between them is intentional — the reward
fires per swing and would otherwise bury the log.

**Fail means:** either the branch never runs (no line at all) or it rewards hostiles
(a line on someone already attacking you, which it must not).

---

## 3. The menu gate — new

**Do:** right-click a survivor before doing anything to it, then again after test 2.

**Pass, before:**
```
Survivor_01  [neutral 0]
   Follow me  (needs 25 trust)      <- greyed out
```
**Pass, after:** the same entry, enabled.

**Fail means:** no submenu at all (the click missed — an NPC mid-step is often on the next
square; try clicking slightly south or west of it), or the option is enabled at low trust.

---

## 4. Follow me / Leave me — new

**Do:** with trust at 25 or more, choose **Follow me**. Walk somewhere. Then **Leave me**.

**Pass:** it follows you and keeps up. The submenu now offers Leave me instead. After
Leave me it stops following.

**Fail means:** it accepts but stands still → `brain.master` did not take, and the
`SwitchProgram` delegation is wrong.

---

## 5. Engagement range — regression

**Do:** stand with survivors near you, with zombies visible but far (more than 8 tiles).

**Pass:** they hold position instead of running at them. A shrugging idle animation is
correct here, not a bug — it is Bandits' "nothing to do" branch.

**Fail means:** they sprint off. The wrapper in `ScenesRelationsEngagement.lua` did not
load.

---

## 6. Threat, even odds — new

**Do:** with four or more survivors together, lead one or two zombies to them.

**Pass:**
```
SREL| THREAT <name> | zombies=2 friends=4 brave=true -> fight
```
Everybody stands and fights.

---

## 7. Threat, outnumbered — the main new scenario

**Do:** get a large group of zombies (eight or more) moving toward two or three survivors
standing near a house with windows.

**Pass:** the log splits them, and you can see it on screen:
```
SREL| THREAT <name> | zombies=9 friends=2 brave=false -> flee
SREL| THREAT <name> -> shelter at 10432,9871 (closed)
SREL| THREAT <name> | zombies=9 friends=2 brave=true  -> fight
```
The cautious ones run for a window and climb in. The brave ones stay out.

**Expect up to ~6 seconds of delay.** The decision runs on `EveryOneMinute`, which is an
in-game minute — about 6 real seconds at `DayLength=4`. It decides posture, not swings.

**Fail means:**
- `-> flee` with no `shelter at` line → no window within 8 tiles. Move the test next to a
  house and repeat before reporting anything.
- They walk to the window and stop outside → the `OpenWindow` task did not complete.
- They walk there and then wander off → expected for now. We push one task in front of
  their program; when it drains, their program resumes. Note it, do not treat it as a
  failure.

---

## 8. The same survivor is always the same person

**Do:** repeat test 7 twice with the same spawned group.

**Pass:** the ones that fled the first time flee again. `brain.rnd` is rolled once at
spawn, so bravery is a trait, not a die roll.

**Fail means:** the roles shuffle → we are reading the wrong field.

---

## 9. Persistence

**Do:** build trust with one survivor, save, quit to menu, reload.

**Pass:** the number in the right-click label survives.

**Known caveat:** the hostile flag may not. `Bandit.SetHostile` (`Bandit.lua:588`) has its
`BanditBrain.Update` call commented out, so it lives only in the client-side brain mirror.
Trust is in `getModData()` and does persist. If the number survives and the flag does not,
that is the known upstream behaviour, not our bug.

---

## What to send back

`console.txt`, plus one line per test: number, pass or fail, and what you saw. If
something threw, the stack trace is worth more than a description.

Do not delete the log between tests — the frame numbers are how we reconstruct the order.
