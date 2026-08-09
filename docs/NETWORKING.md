# Connecting this box to the Windows PC

## First: kill the wrong mental model

The PZ dedicated server is **not** an HTTP API and there is no tunnel URL like a VS Code
port forward. It speaks a raw binary game protocol over **UDP**, and the client joins by
typing an IP and a port. Nothing to `curl`, no REST, no web UI, no shareable link.

Second thing: **the server does not send your mod to the client.** Steam Workshop mods get
downloaded by the client from Steam. An unpublished local mod does not — the client must
already have the files. So there are two independent problems:

| Channel | Carries | Solved by |
|---|---|---|
| A. File sync | the mod source | git (or rsync) |
| B. Game session | live gameplay | UDP 16261/16262 |

You do **not** need channel B to test a mod. Singleplayer on the Windows PC needs only A.

---

## Verified config on this machine

```
LAN IP        192.168.0.194/24   (wlan0, gateway 192.168.0.1)
server dir    ~/Docs/Workspace/PZ/pzserver
config        ~/Zomboid/Server/servertest.ini
  DefaultPort=16261     # UDP, the port clients connect to
  UDPPort=16262         # UDP, secondary
  Public=false          # not listed in the public browser — correct for dev
  Open=true             # no whitelist
  Mods=                 # empty, fill with mod ids
  WorkshopItems=        # empty, fill with Workshop ids (e.g. 3268487204 for Bandits)
firewall      ufw installed
```

---

## Channel A — getting the mod onto the Windows PC

Simplest option, and it matches how you already work: **git**.

**This repo holds three mods, not one.** Two projects, three mod folders, three ids:

| Repo path | Mod folder | `id=` | What it is |
|---|---|---|---|
| `mods/ScenesProject/Contents/mods/ScenesRelations/` | `ScenesRelations` | `scenesRelations` | the main mod — NPC relationships and behaviour |
| `mods/ScenesProject/Contents/mods/ScenesDoctor/` | `ScenesDoctor` | `scenesDoctor` | memory/perf diagnostics, emits `SDOC|` lines |
| `mods/TLOUProject/Contents/mods/TLOUFactions/` | `TLOUFactions` | `tlouFactions` | the faction layer |

Note the shape difference. `~/Zomboid/mods/` takes the **mod folder directly** — the thing
containing `42/`, not the `Contents/mods/` wrapper above it. The `Contents/` wrapper exists
only for `~/Zomboid/Workshop/`, which is the upload staging area. So on Windows each of the
three lands as:

```
%USERPROFILE%\Zomboid\mods\ScenesRelations\42\...
%USERPROFILE%\Zomboid\mods\ScenesDoctor\42\...
%USERPROFILE%\Zomboid\mods\TLOUFactions\42\...
```

Deploy becomes `git pull` on the Windows side. No new infrastructure, full history, and it
also gets you rollback when a change breaks the save.

On this box the same copy is done by `tools/sync-mods.sh`, which flattens all three plus the
vendored mods into `~/Zomboid/mods/` for the headless smoke test. Read it before inventing a
Windows-side script — it already documents why symlinks cannot be used here.

Alternative if you want it push-based: `rsync -av --delete` over ssh, or Syncthing for
continuous sync. Same result, more moving parts.

---

## Channel B — joining the server from Windows

### Same wifi (both on 192.168.0.x) — nothing to install

1. On Arch, edit `~/Zomboid/Server/servertest.ini`. Mod ids are semicolon-separated. What is
   actually in the working config on this box today, verbatim:
   ```ini
   Mods=tlouFactions;scenesDoctor;scenesRelations;Bandits2
   WorkshopItems=
   ```
   Two things worth reading twice:
   - **Bandits is `Bandits2`, and it belongs in `Mods=` like anything else.** A dependency is
     not implicit; if it is not listed it is not loaded.
   - **`WorkshopItems=` is empty on purpose here.** That field tells the server to download
     from Steam. This box does not need it — `tools/sync-mods.sh` copies the vendored Bandits
     straight into `~/Zomboid/mods/`, which is the whole point of `vendor/` being pinned by
     `deps.lock.json`. On a machine without that sync you would put `3268487204` here instead.
2. Start it:
   ```bash
   cd ~/Docs/Workspace/PZ/pzserver
   ./start-server.sh -adminpassword devpass
   ```
3. Open the ports if ufw is active:
   ```bash
   sudo ufw allow 16261:16262/udp
   ```
4. On Windows: Project Zomboid → Join → Add server → `192.168.0.194`, port `16261`.

The Windows client still needs the mod files locally (channel A) — the server will not
send them.

`192.168.0.194` is DHCP and can change. Reserve it in the router, or use the Tailscale
address below which never changes.

### Different networks — the closest thing to a VS Code tunnel

**Tailscale.** Mesh VPN, both machines join your private network, each gets a permanent
`100.x.y.z` address that works from anywhere. No port forwarding, no exposing anything to
the internet.

```bash
yay -S tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
```

Install the Windows client, log in with the same account, then join
`100.x.y.z:16261` instead of the LAN IP. That address is stable — it survives wifi changes,
DHCP, and moving between networks.

Do **not** port-forward 16261 on the router for this. A dev server with a known admin
password reachable from the open internet is a real exposure, and `Public=false` only hides
it from the server browser — it does not block anything.

---

## Channel C — getting `console.txt` back

The other two channels move the mod *toward* Windows. This one is the return trip, and it is
the operation that happens most often, because **`console.txt` is the only debugger this
project has** and it is written on a machine with no agent on it.

On Windows the game writes to:

```
%USERPROFILE%\Zomboid\console.txt
```

**The method is manual, and that is a decision, not an omission.** Upload the file to the
GitHub repo (or paste the relevant slice into the conversation) after a play session. It is
the simplest thing that works and it needs nothing installed on either side.

Two automated alternatives were evaluated on 2026-08-08 and **rejected**:

- **A webhook or listener inside the mod is impossible.** Project Zomboid's Lua has no
  network API at all — no HTTP client, no sockets, nothing. Grepping all 2,680 Lua files in
  `pzserver/media/lua/` returns zero hits. The only write primitive is `getFileWriter()`, and
  it writes inside the `Zomboid` folder. Any "streaming" design would end up tailing a file.
- **An SMB share on Windows mounted here over cifs** would work and would remove the manual
  step entirely — `mount.cifs` and `rsync` are already installed on this box. It was declined
  as not worth the setup and the DHCP fragility. Revisit only if the manual upload becomes the
  bottleneck.

Once the file is on this box, run it through the digester rather than reading it whole:

```bash
./tools/logdoctor.py path/to/console.txt          # collapses repeated errors into signatures
./tools/logdoctor.py path/to/console.txt --top 25
```

A runaway loop shows up as one signature with a huge count. `ScenesDoctor`'s `SDOC|MEM`
samples get charted by the same tool.

**Read `ASSERT` first, always.** `ScenesRelationsAssert.lua` runs in-game at startup and
checks that the engine is shaped the way the code believes. A `FAIL` there invalidates every
behavioural observation below it — see `docs/PLAN-STATUS.md` for the count to expect.

---

## Which loop to actually use

```
Day-to-day (fast):
  edit here → pz-review → pz-verify smoke test → git push
            → git pull on Windows → SINGLEPLAYER
            → console.txt back here (channel C) → logdoctor.py

Only when testing multiplayer behavior:
  ... → start server here → join from Windows over LAN/Tailscale
```

The `pz-review` step is not optional — see the delegation cycle in `CLAUDE.md`. And remember
what the smoke test cannot see: **a dedicated server never executes `media/lua/client/`**,
which is most of ScenesRelations. A PASS there means the shared and server halves load,
nothing more. The in-game assertion harness is the only net for the client half.

Bandits NPC logic is server-side, and in singleplayer the client *is* the host — so
singleplayer already exercises the faction code. Reach for channel B when you specifically
need to test how factions behave with two real players.
