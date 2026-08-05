#!/usr/bin/env python3
"""Query the Steam Workshop for Project Zomboid (appid 108600).

Two backends:
  details  -> ISteamRemoteStorage/GetPublishedFileDetails  (NO api key needed)
  search   -> IPublishedFileService/QueryFiles             (needs STEAM_API_KEY)

Get a free key at https://steamcommunity.com/dev/apikey (any domain works).

Usage:
    ./workshop.py details 3268487204 3403180543
    ./workshop.py watch                  # reads watchlist.txt next to this file
    ./workshop.py search "the last of us" --tag "Build 42" --n 30
    ./workshop.py trending --tag "Build 42" --n 30
"""
import argparse
import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone

APPID = 108600
DETAILS = "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"
QUERY = "https://api.steampowered.com/IPublishedFileService/QueryFiles/v1/"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def _load_env():
    """Read STEAM_API_KEY from .env at the repo root, if it is there.

    .gitignore has promised that file holds "Local secrets (STEAM_API_KEY etc.)" since the
    first commit, and nothing ever read it -- so the key had to be exported by hand in every
    new shell and the promise was a trap. A real environment variable still wins; this only
    fills the gap.
    """
    path = os.path.join(ROOT, ".env")
    if not os.path.isfile(path):
        return
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, _, value = line.partition("=")
            os.environ.setdefault(name.strip(), value.strip().strip("'\""))


_load_env()


def _post(url, fields):
    data = urllib.parse.urlencode(fields, doseq=True).encode()
    with urllib.request.urlopen(urllib.request.Request(url, data=data), timeout=30) as r:
        return json.load(r)


def _get(url, params):
    with urllib.request.urlopen(f"{url}?{urllib.parse.urlencode(params, doseq=True)}", timeout=30) as r:
        return json.load(r)


def fetch_details(ids):
    """Keyless. Silently drops ids that do not exist."""
    if not ids:
        return []
    fields = [("itemcount", len(ids))]
    fields += [(f"publishedfileids[{i}]", pid) for i, pid in enumerate(ids)]
    out = _post(DETAILS, fields)["response"].get("publishedfiledetails", [])
    return [f for f in out if f.get("title")]


def fetch_query(text="", tags=(), n=30, sort=0):
    """sort: 0=vote, 1=publish date, 3=trend, 21=last updated. Needs key."""
    key = os.environ.get("STEAM_API_KEY")
    if not key:
        sys.exit("STEAM_API_KEY not set -> https://steamcommunity.com/dev/apikey")
    p = {
        "key": key, "appid": APPID, "query_type": sort, "numperpage": n,
        "return_metadata": "true", "return_tags": "true", "return_short_description": "true",
        "search_text": text, "match_all_tags": "true",
    }
    for i, t in enumerate(tags):
        p[f"requiredtags[{i}]"] = t
    return _get(QUERY, p)["response"].get("publishedfiledetails", [])


def show(items, verbose=False):
    def ts(v):
        return datetime.fromtimestamp(v, timezone.utc).strftime("%Y-%m-%d") if v else "-"

    items = sorted(items, key=lambda f: -int(f.get("subscriptions") or 0))
    for f in items:
        subs = f.get("subscriptions")
        subs = f"{int(subs):,}" if subs is not None else "?"
        print(f"{f['publishedfileid']:>12}  {subs:>10} subs  upd {ts(f.get('time_updated'))}  {f.get('title')}")
        if verbose:
            print(f"{'':14}tags: {', '.join(t['tag'] for t in f.get('tags', []))}")
            print(f"{'':14}https://steamcommunity.com/sharedfiles/filedetails/?id={f['publishedfileid']}")
    print(f"\n{len(items)} items")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-v", "--verbose", action="store_true")
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("details")
    d.add_argument("ids", nargs="+")
    sub.add_parser("watch")
    for name in ("search", "trending", "recent"):
        s = sub.add_parser(name)
        s.add_argument("text", nargs="?", default="")
        s.add_argument("--tag", action="append", default=[])
        s.add_argument("--n", type=int, default=30)
    a = ap.parse_args()

    if a.cmd == "details":
        show(fetch_details(a.ids), a.verbose)
    elif a.cmd == "watch":
        with open(os.path.join(HERE, "watchlist.txt")) as fh:
            ids = [ln.split("#")[0].strip() for ln in fh]
        show(fetch_details([i for i in ids if i.isdigit()]), True)
    else:
        sort = {"search": 0, "trending": 3, "recent": 21}[a.cmd]
        show(fetch_query(a.text, a.tag, a.n, sort), a.verbose)


def _selfcheck():
    """python3 workshop.py --selfcheck   (hits the live keyless endpoint)"""
    got = fetch_details(["3268487204", "1"])  # Bandits NPC + a bogus id
    assert len(got) == 1, f"bogus id should be filtered, got {len(got)}"
    assert int(got[0]["subscriptions"]) > 100_000, got[0]["subscriptions"]
    print("selfcheck ok:", got[0]["title"])


if __name__ == "__main__":
    if "--selfcheck" in sys.argv:
        _selfcheck()
    else:
        main()
