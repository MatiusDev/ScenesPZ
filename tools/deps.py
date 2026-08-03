#!/usr/bin/env python3
"""Track the Workshop mods ScenesPZ builds against, and detect drift.

Slayer ships fixes same-day. Developing against a stale vendored copy means
debugging bugs that no longer exist -- which already cost us one session.

    ./deps.py check     compare deps.lock.json against Steam. exit 1 on drift.
    ./deps.py update    download drifted mods into vendor/, rewrite the lock
    ./deps.py lock      record whatever is vendored right now as the baseline

`check` needs no Steam key and no steamcmd. `update` needs steamcmd.
"""
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from workshop import fetch_details  # keyless GetPublishedFileDetails

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCK = os.path.join(ROOT, "deps.lock.json")
APPID = 108600


def iso(ts):
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load():
    with open(LOCK) as fh:
        return json.load(fh)


def save(data):
    data["checked_at"] = iso(int(datetime.now(timezone.utc).timestamp()))
    with open(LOCK, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")


def compare(data):
    """Returns [(mod_id, entry, live_updated_ts)] for every drifted mod."""
    live = {f["publishedfileid"]: f for f in fetch_details(list(data["mods"]))}
    drift = []
    for mod_id, entry in data["mods"].items():
        f = live.get(mod_id)
        if not f:
            print(f"  ?? {mod_id} {entry['name']} — not returned by Steam")
            continue
        upstream, pinned = iso(f["time_updated"]), entry["steam_updated"]
        if upstream != pinned:
            print(f"  DRIFT  {entry['name']}\n         locked {pinned} -> upstream {upstream}")
            drift.append((mod_id, entry, f["time_updated"]))
        else:
            print(f"  ok     {entry['name']}  ({pinned})")
    return drift


def download(mod_id, dest):
    """steamcmd anonymous download, then move into vendor/. Keeps the old copy as .old."""
    staging = f"/tmp/pzdeps-{mod_id}"
    shutil.rmtree(staging, ignore_errors=True)
    subprocess.run(
        ["steamcmd", "+force_install_dir", staging, "+login", "anonymous",
         "+workshop_download_item", str(APPID), str(mod_id), "+quit"],
        check=True,
    )
    src = os.path.join(staging, "steamapps/workshop/content", str(APPID), str(mod_id))
    if not os.path.isdir(src):
        raise SystemExit(f"steamcmd reported success but {src} is missing")
    target = os.path.join(ROOT, dest)
    # Keep exactly one previous copy so a regression can be diffed, never more.
    shutil.rmtree(target + ".old", ignore_errors=True)
    if os.path.isdir(target):
        os.rename(target, target + ".old")
    shutil.move(src, target)
    shutil.rmtree(staging, ignore_errors=True)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    data = load()

    if cmd == "check":
        print(f"game build {data['game_build']} | locked {data['checked_at']}")
        drift = compare(data)
        if drift:
            print(f"\n{len(drift)} mod(s) drifted. Run: ./tools/deps.py update")
            return 1
        print("\nall dependencies current")
        return 0

    if cmd == "update":
        drift = compare(data)
        if not drift:
            print("\nnothing to update")
            return 0
        for mod_id, entry, upstream_ts in drift:
            print(f"\ndownloading {entry['name']} ...")
            download(mod_id, entry["vendor_path"])
            entry["steam_updated"] = iso(upstream_ts)
            entry["vendored_at"] = iso(int(datetime.now(timezone.utc).timestamp()))
        save(data)
        print(f"\nupdated {len(drift)} mod(s); deps.lock.json rewritten")
        print("On the gaming PC: unsubscribe and resubscribe on Steam to match.")
        return 0

    if cmd == "lock":
        live = {f["publishedfileid"]: f for f in fetch_details(list(data["mods"]))}
        now = iso(int(datetime.now(timezone.utc).timestamp()))
        for mod_id, entry in data["mods"].items():
            if mod_id in live:
                entry["steam_updated"] = iso(live[mod_id]["time_updated"])
                entry["vendored_at"] = now
        save(data)
        print("baseline recorded")
        return 0

    raise SystemExit(__doc__)


if __name__ == "__main__":
    sys.exit(main())
