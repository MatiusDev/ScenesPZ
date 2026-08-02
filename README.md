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

Clone, then link the Workshop project into the game's cache directory. Use **only** this
link — a second copy under `Zomboid/mods/` will clash with it and silently shadow changes.

```cmd
:: Windows (needs admin or Developer Mode)
git clone <repo> C:\dev\PZ
mklink /D "%USERPROFILE%\Zomboid\Workshop\TLOUProject" C:\dev\PZ\mods\TLOUProject
```

```bash
# Linux / macOS
git clone <repo> ~/dev/PZ
ln -s ~/dev/PZ/mods/TLOUProject ~/Zomboid/Workshop/TLOUProject
```

Enable the mod in-game under Mods. Deploy updates with `git pull` plus a game restart —
Project Zomboid has no hot reload.

## Requirements

- Project Zomboid Build 42 (42.20.0)
- [Bandits NPC](https://steamcommunity.com/sharedfiles/filedetails/?id=3268487204) — declared in `mod.info` as `require=\Bandits2`
