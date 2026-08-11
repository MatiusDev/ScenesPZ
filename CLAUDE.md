# PZ Mod Workspace — Project Rules

Project Zomboid mod development. Build 42 (stable 42.20.0). Target: TLOU-style NPC
factions as an addon to the Bandits framework.

## Machine roles

| Machine | Role |
|---|---|
| This box (Arch, `192.168.0.194`) | source of truth, git, headless server smoke test. **No game client.** |
| User's Windows PC | owns Project Zomboid. Where the mod is actually played and where it gets uploaded to the Workshop. |

`pzserver/` is a full 42.20.0 install without rendering. `pzserver/media/` (2,680 Lua files,
1,004 script files) is the **authoritative API reference**. Prefer it over the wiki.

## Architecture principles

These are not style preferences — each one maps to a specific way PZ mods break.

1. **One namespace, globally.** Every mod's Lua loads into the same state as the base game.
   Everything you declare is prefixed and hangs off a single mod table. Unprefixed globals
   are how two mods silently break each other.
2. **Data and behavior are separate layers.** Anything expressible as `scripts/*.txt`, XML,
   or a Bandits `.txt` stays declarative. Lua is only for behavior that data cannot express.
   Declarative content survives game updates; Lua does not.
3. **The client/server boundary is real even in singleplayer.** Singleplayer is a host plus
   one client. World mutation belongs in `lua/server/`. Code that works alone and desyncs in
   multiplayer is the most common PZ mod defect.
4. **Extend, never replace.** Wrap vanilla functions, keep the original call. Overwriting is
   what makes mods mutually exclusive.
5. **Never write an identifier you have not seen in a file.** Fabricated item ids fail
   silently at runtime and cost a full game restart to detect. Grep `pzserver/media/` first.
6. **Assume no hot reload.** Every mistake costs the user a restart and a context switch to
   another machine. Correctness over speed.

## Delegation

| Work | Agent |
|---|---|
| "how does vanilla do X", finding ids, Workshop lookups | `pz-research` |
| `mod.info`, `scripts/*.txt`, `clothing/*.xml`, bandits `.txt` | `pz-data` |
| anything under `media/lua/` | `pz-lua` |
| headless server smoke test, log triage | `pz-verify` |
| reviewing a diff before the user tests it | `pz-review` |

Orchestrator (me) handles: architecture decisions, folder layout, cross-cutting naming,
git, network/deploy, and reading `console.txt` the user pastes.

### The cycle — a writer's output is not done when the writer says it is

```
pz-research  ->  writer (pz-lua | pz-data)  ->  pz-review  ->  pz-verify  ->  user tests
```

Six rules hold this together, and each one is here because skipping it cost something:

1. **Research before writing.** `pz-research` first, then a writer. Never a writer alone on
   a question that starts with "how does the game/Bandits do X".
2. **No writer output reaches a commit, a sync, or the gaming PC without `pz-review`.**
   Not "when it looks risky" — always. On 2026-08-08 `pz-lua` correctly extracted a
   walk-then-act primitive and silently killed the idle-clothing behaviour by wiring it into
   a caller with no re-entry motor. Lint passed, the diff read beautifully, and it went to
   disk unreviewed because nothing in this file said review was mandatory. Now it does.
3. **There is no such thing as a self-review, and attempting one is worse than skipping it.**
   The orchestrator reviewing its own work has now shipped two defects in two days that an
   independent `pz-review` then found in one pass. On 2026-08-10 a self-review "fixed" a
   cross-floor predicate at one call site and left the same predicate with INVERTED POLARITY at
   the other, breaking the feature it was fixing and regressing behaviour that already worked.
   The author is blind in the same place twice; that is what makes it structural rather than
   careless.

   So: **always launch `pz-review`.** Never substitute reading your own diff for it, however
   well you understand the change and however small it looks. A self-review costs tokens and
   buys confidence that is not warranted, which is the worst trade available.

   **If a spend limit kills the review agent**, the change is UNREVIEWED — say so plainly and do
   not commit on the strength of your own reading. When the user next says to continue after a
   spend-limit stop, **relaunch the review before doing anything else**. A half-finished piece of
   work is resumed; a killed review is re-run.

4. **A writer that produced no report produced no verified work, and it does not get
   committed.** A subagent can die mid-task — spend limits, timeouts, context exhaustion —
   and leave lint-clean files with no account of what it changed or what it could not check.
   Treat those files as a stranger's patch: review them before believing them, whatever
   `lint.sh` says.

   **The second half of that sentence is new, and it is new because the first half was not
   enough.** On 2026-08-10 a writer applying eight review findings died on a spend limit
   after fixing four. `lint.sh` passed, `audit.py` passed, the diff read beautifully — and it
   was committed and pushed with the other four unfixed, plus two constants that had been
   declared and never wired. Green tooling on a half-finished change is not evidence of
   anything; it is what a half-finished change looks like.

   So: **a dead agent's work stays uncommitted until somebody finishes it and `pz-review` has
   seen the whole thing.** If you are resuming after a spend-limit stop, the first question is
   "what did it not get to", and the answer comes from re-checking every item on the list it
   was given — not from reading the diff and judging it complete.

5. **Measure whether the case happens before building the lever for it.** A play report says
   what it felt like; the log says what occurred, and they are not the same question.

   On 2026-08-10 a door-opening action was built, correctly and with good citations, for
   obstacle kind `door`. The obstacle census across two sessions was **10 `solid`, 6 `clear`,
   2 `locked`, 2 `hop`, and 0 `door`** — the measurement already existed, in the log, from a
   test written for exactly this decision. In a full play session afterwards, `ToggleDoor`
   fired zero times and `ClimbFence` once. The code was not wrong. It was aimed at a case
   that does not occur, while 16 of 20 real jams went untouched.

   Before writing a lever, grep `logs/` for how often its trigger actually fires. If nothing
   in the log can answer that, say so and add the instrument first — an instrument that
   settles a design question is cheaper than the feature it saves you from writing.

6. **`pz-verify` after every change touching loadable files**, and remember what it cannot
   see: a dedicated server never executes `media/lua/client/`, which is most of this mod. A
   PASS there means "the shared and server halves load", nothing more.

Single-file mechanical edits stay inline. Do not delegate a one-line fix — but rule 2 still
applies to the diff, and inline work is reviewed by the same agent as delegated work.

Before building NPC behavior, `pz-lua` and `pz-research` read `docs/BANDITS-API.md` first.
It is a lookup table, not background reading — the point is to answer "does this already
exist?" in one file instead of re-deriving it from 22,458 lines every session.

## Dependency freshness — blocking gate

Slayer ships fixes to Bandits **same-day**. We already lost a session debugging
`IsoObject:transmitCompleteItemToServer()` — a bug the author had fixed hours earlier.
Working against a stale vendored copy is the single most expensive failure mode in this
project.

`deps.lock.json` records the exact upstream version every dependency is pinned to.

**Before any work that reads, calls, or extends a vendored mod, run:**

```bash
./tools/deps.py check
```

- **all current** — proceed.
- **DRIFT** — stop. Report the drift to the user. Do not diagnose a bug, quote a line
  number, or propose a fix against a stale copy; the finding may already be obsolete.
  Resolve with `./tools/deps.py update`, which re-downloads and rewrites the lock.

This gate is mandatory for `pz-research`, `pz-lua`, and `pz-verify`. It is skippable only
for work that touches no vendored code at all — our own declarative data, docs, tooling.

After an update the gaming PC must be resynced too: unsubscribe and resubscribe on Steam,
then verify with the check in `docs/NETWORKING.md`. `deps.lock.json` is the shared source
of truth for both machines and is committed on every version change.

## Conventions

- Mod id prefix: `tlou` (lua table `TLOU`, item module `TLOU`, command module `"TLOU"`).
- Lowercase filenames always — the Windows client hides extensions and Linux is case-sensitive.
- English in all artifacts: code, comments, mod descriptions, commit messages. Conversation
  with the user is Spanish.
- Conventional commits. No AI attribution.
- `Contents/` is the only uploaded directory. Tools, docs, and `.git` live outside it.

## Reference

- `docs/CODE-REVIEW-RULES.md` — eleven rules, each written after a real bug that cost
  a play session. `pz-review` reads it before every review; read it before writing code
  that touches the engine.
- `tools/audit.py` — the mechanical half of a review, eight checks, each added after a real
  defect. Run it before asking for a review, not after: every finding it reports is one a
  human reviewer would otherwise spend tokens re-deriving. Four of the checks BLOCK —
  `latches`, `deadconst`, `vendor`, `lua51`. `deadconst` is the newest and the most
  counter-intuitive: a constant declared with a careful comment and read by nothing is worse
  than a missing feature, because the comment is exactly the evidence a reviewer checks for.
  It has caught that pattern four times.
- `docs/TODO.md` — things seen in play that no stage has claimed yet. Add to it rather
  than derailing the open stage.
- `docs/PLAN-STATUS.md` — **start here.** An index, under a screen: which block is open and
  where everything else lives. It points at two files whose shapes are deliberate and must
  not be mixed:
  - `docs/TESTING-NOW.md` — the open round only, **rewritten whole** each time. When a round
    closes, its tests move out; they are never left behind with a verdict appended.
  - `docs/TEST-LOG.md` — **append-only** history: every round, its verdict, and what it
    taught. Correct a wrong entry with a new one, never by editing the old.

  All three are Spanish, on purpose — the user reads them with the game open. This is the one
  exception to English-in-all-artifacts.
- `docs/plans/` — the staged roadmap from here to the full PRD. `README.md` lists all
  eleven stages with their dependencies; only the current and next stage are written in
  detail, on purpose.
- `docs/BANDITS-API.md` — **read before writing any NPC behavior.** Every lever Bandits
  already gives us: 49 task actions with their fields, 8 programs, the full `Bandit.*` API,
  the brain record, how persistence works, and the known traps. It exists so nobody
  rebuilds something that already ships.
- `docs/NPC-AI-ARCHITECTURE.md` — **the big picture.** The layer model (needs, perception,
  appraisal, decision, execution, memory, social), the two extension seams and when to
  graduate from one to the other, and what counts as done. Read before any design argument.
- `docs/TEST-RUNS.md` — the ordered test protocol for the gaming PC, with pass criteria and
  the exact log lines each test must produce.
- `docs/NPC-BEHAVIOR-PLAN.md` — the staged plan for NPC behaviour, what each stage proves,
  the verified levers, the identifiers that do **not** exist in 42.20, and the tuning log
  with the reason behind every number. Update it whenever a value or a stage changes.
- `docs/PZ-MODDING-MAP.md` — folder-by-folder map, mod.info fields, B41/B42 differences
- `docs/NETWORKING.md` — how this box and the Windows PC connect
- `tools/workshop.py` — Steam Workshop CLI (`watch`, `details`, `search`, `trending`)
