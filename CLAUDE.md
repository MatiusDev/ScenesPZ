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
git, network/deploy, and reading `console.txt` the user pastes. Research before writing —
`pz-research` first, then a writer. `pz-verify` after every change that touches loadable files.

Single-file mechanical edits stay inline. Do not delegate a one-line fix.

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
- `docs/PLAN-STATUS.md` — **start here.** Which stage is open, and exactly what the user
  must test in game to close it. One page, kept current.
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
