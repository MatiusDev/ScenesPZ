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

On this box, `mods/TLOUProject/` is the repo. On Windows, clone it so the mod folder lands
where the game looks:

```
%USERPROFILE%\Zomboid\mods\TLOUFactions\
```

Note the shape difference. `~/Zomboid/mods/` takes the **mod folder directly** — not the
`Contents/mods/` wrapper. The `Contents/` wrapper only exists for `~/Zomboid/Workshop/`,
which is the upload staging area.

Deploy becomes `git pull` on the Windows side. No new infrastructure, full history,
and it also gets you rollback when a change breaks the save.

Alternative if you want it push-based: `rsync -av --delete` over ssh, or Syncthing for
continuous sync. Same result, more moving parts.

---

## Channel B — joining the server from Windows

### Same wifi (both on 192.168.0.x) — nothing to install

1. On Arch, edit `~/Zomboid/Server/servertest.ini`:
   ```ini
   Mods=tlouFactions
   WorkshopItems=3268487204
   ```
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

## Which loop to actually use

```
Day-to-day (fast):
  edit here → pz-verify smoke test → git push → git pull on Windows → SINGLEPLAYER

Only when testing multiplayer behavior:
  ... → start server here → join from Windows over LAN/Tailscale
```

Bandits NPC logic is server-side, and in singleplayer the client *is* the host — so
singleplayer already exercises the faction code. Reach for channel B when you specifically
need to test how factions behave with two real players.
