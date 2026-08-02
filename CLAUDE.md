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

Orchestrator (me) handles: architecture decisions, folder layout, cross-cutting naming,
git, network/deploy, and reading `console.txt` the user pastes. Research before writing —
`pz-research` first, then a writer. `pz-verify` after every change that touches loadable files.

Single-file mechanical edits stay inline. Do not delegate a one-line fix.

## Conventions

- Mod id prefix: `tlou` (lua table `TLOU`, item module `TLOU`, command module `"TLOU"`).
- Lowercase filenames always — the Windows client hides extensions and Linux is case-sensitive.
- English in all artifacts: code, comments, mod descriptions, commit messages. Conversation
  with the user is Spanish.
- Conventional commits. No AI attribution.
- `Contents/` is the only uploaded directory. Tools, docs, and `.git` live outside it.

## Reference

- `docs/PZ-MODDING-MAP.md` — folder-by-folder map, mod.info fields, B41/B42 differences
- `docs/NETWORKING.md` — how this box and the Windows PC connect
- `tools/workshop.py` — Steam Workshop CLI (`watch`, `details`, `search`, `trending`)
