# ScenesPZ

Project Zomboid Build 42 mod workspace. Post-apocalyptic scenario mods — The Last of Us
meets The Walking Dead. Adds NPC factions
(WLF, FEDRA, Seraphites) as an addon to the [Bandits NPC](https://steamcommunity.com/sharedfiles/filedetails/?id=3268487204)
framework.

## Layout

```
mods/TLOUProject/       the mod, laid out as a Steam Workshop project
  Contents/             the only directory uploaded to the Workshop
docs/                   modding reference and network setup
tools/workshop.py       Steam Workshop CLI
.claude/agents/         subagent definitions for this project
CLAUDE.md               architecture rules and delegation routing
```

`pzserver/` is gitignored — it is a 6.9 GB dedicated-server install used as a headless
smoke test and as the offline vanilla API reference. Reinstall with:

```bash
steamcmd +force_install_dir <path>/pzserver +login anonymous +app_update 380870 validate +quit
```

## Setup on a machine that owns the game

Clone anywhere, then **copy** the mods into the game's cache directory.

```cmd
git clone https://github.com/MatiusDev/ScenesPZ.git C:\dev\ScenesPZ
cd C:\dev\ScenesPZ
tools\sync-mods.bat
```

```bash
# Linux / macOS
git clone https://github.com/MatiusDev/ScenesPZ.git ~/dev/ScenesPZ
~/dev/ScenesPZ/tools/sync-mods.sh
```

**Do not symlink the mods instead.** Project Zomboid resolves a symlinked mod directory
to its absolute target and then re-appends it to the mods folder, yielding paths like
`Zomboid/mods/home/user/dev/scenespz/...`. `mod.info` is still found, so the mod reports
as loaded while every script silently fails — a full day of debugging for nothing.
Verified on 42.20.0.

Deploy an update: `git pull`, rerun the sync script, restart the game. There is no hot reload.

## Mods in this repo

| Mod | id | What it does |
|---|---|---|
| ScenesDoctor | `scenesDoctor` | Diagnostics only. Wraps Bandit globals with call counters, samples the Lua heap, prefixes output with `SDOC\|`. No gameplay, no dependencies. |
| TLOUFactions | `tlouFactions` | WLF / FEDRA / Seraphite clans for Bandits. Requires Bandits. |

Analyze a run with `tools/logdoctor.py ~/Zomboid/console.txt` (Windows:
`%USERPROFILE%\Zomboid\console.txt`). It collapses repeated errors into signatures, so a
runaway loop appears as one entry with a huge count.

## Requirements

- Project Zomboid Build 42 (42.20.0)
- [Bandits NPC](https://steamcommunity.com/sharedfiles/filedetails/?id=3268487204) — declared in `mod.info` as `require=\Bandits2`
