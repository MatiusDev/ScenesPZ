# Where we are, and what to test next

One page. Updated every time a stage opens or closes. If this file and anything else
disagree, this file is the one that is stale — fix it.

Full roadmap: [`docs/plans/README.md`](plans/README.md).

---

## Open right now

| Stage | State |
|---|---|
| [00 — Test world](plans/00-test-world.md) | built, partially confirmed |
| [01 — Durable memory](plans/01-durable-memory.md) | built, **the unload test never got run** |
| [02 — Interaction wheel](plans/02-interaction-wheel.md) | built, never run |

Next up: [03 — Idle life](plans/03-idle-life.md) — picking things up, wearing them, looting
where they live.

### What the last run actually told us

- Trust rises properly when you fight beside somebody. That part works.
- **The right-click menu made everything else hard to test.** That is why stage 02 exists
  and why it jumped ahead of the rest of the memory work.
- The NPCs feel empty between fights. Correct, and stage 03 is the answer.
- Two questions came back unanswered and they are still the two that matter most: the
  cell-unload test, and whether the halo text appeared on screen.

---

## Before you start

```bash
tools/sync-mods.sh
```

Then open **Options → Key Bindings** and check where `Talk to survivor` landed. Default is
**V**. If another mod already owns V, rebind it here — no code change needed.

A new game is not required this time. Stage 02 works on any save; only the starting
companion needs a fresh one.

---

## What to test, in order

### 1. The wheel opens

**Do:** stand near a survivor. **Hold V.**

**Pass:** a wheel appears in the centre of the screen with their name and trust underneath,
e.g. `Theodore Kaine   neutral 0`.

`console.txt` shows `SREL| WHEEL opened on … | 2 options`.

**If nothing happens:** check the keybinding first. Then look for `SREL| WHEEL ready` at
startup — if that line is missing, the file did not load.

**If it says "Nobody close enough":** the wheel needs somebody within 8 tiles that you have
line of sight to. Talking through a wall is deliberately not allowed.

---

### 2. Releasing picks the option

**Do:** hold V, move the mouse over a wedge, release.

**Pass:** the action runs. Clicking the wedge instead of releasing must also work.

**Interesting failure:** if releasing closes the wheel without doing anything and
`console.txt` says `WHEEL closed without a selection` every single time, then reading the
slice under the cursor on release is not working and we fall back to click-to-select. Say
so — it is a five-line fix, not a redesign.

---

### 3. Talking raises trust

**Do:** open the wheel on a stranger and pick **Talk**. Repeat.

**Pass:**
- Trust rises `+4` per conversation. Green text appears over **your** head.
- Immediately trying again shows `Talk (nothing more to say yet)` — the cooldown is half an
  in-game hour, roughly three real minutes.
- After enough conversations, `Follow me (needs 25 trust)` becomes plain `Follow me`.

**This is the answer to "conversations that raise points".** It is deliberately slower than
fighting beside somebody — what you risk for a person should outrank what you say to them.
If it feels too slow to be worth doing at all, tell me and the number moves.

---

### 4. Recruit without ever right-clicking

**Do:** take one survivor from stranger to companion using only the wheel.

**Pass:** you never needed the right-click menu once. When that is true I delete it — it
still exists this build only because a wheel that failed to open would have left you with
no way to recruit anybody.

---

### 5. **The one that is still owed — memory across a cell unload**

Test 10 in [`docs/TEST-RUNS.md`](TEST-RUNS.md). This did not get done last time and it is
the single thing that decides whether the mod's premise holds.

1. Get a companion's trust clearly above zero.
2. In `console.txt`, find its `PROBE` line. Write down **both** `id=` and `trust=`.
3. Walk at least ten blocks away. Wait for two `PROBE sweep` lines with no `PROBE` line for
   it in between — that is how you know its cell unloaded.
4. Walk back.

**Pass:** same `id`, same `trust`, `known=true`.

A *different* `id` means recognition needs the fuzzy name-plus-traits fallback and several
later stages slip. That is worth knowing now rather than in a month.

---

### 6. Two seconds of looking at the screen — also still owed

Early in the session `console.txt` prints two `PROBE halo` lines.

**Look at the screen** and tell me whether the words *SCENES probe* appeared above a
survivor's head.

Right now every message goes above **your** head, because that is the only placement proven
to work. If it works on an NPC, one function moves and the whole thing reads far better.
One word answers it.

---

## What to send back

`console.txt`, plus one line per test: number, pass or fail, what you saw.

For test 5, the two `id`/`trust` pairs. For test 6, one word.

Do not delete the log between tests.
