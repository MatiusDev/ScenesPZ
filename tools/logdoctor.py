#!/usr/bin/env python3
"""Digest a Project Zomboid console.txt / server-console.txt.

Two jobs:
  1. Collapse repeated errors into signatures. A runaway loop shows up as ONE
     signature with a huge count -- that is the thing eating RAM.
  2. Chart the SDOC|MEM samples emitted by the ScenesDoctor mod.

    ./logdoctor.py ~/Zomboid/console.txt
    ./logdoctor.py ~/Zomboid/console.txt --top 25
"""
import argparse
import re
from collections import Counter, defaultdict

# Strip anything that differs between two occurrences of the SAME error, so
# repeats collapse: timestamps, frame counters, coords, hex ids, line numbers.
NOISE = [
    (re.compile(r"\bf:\d+\s+st:[\d,]+"), ""),          # f:0 st:33,065,108
    (re.compile(r"\b\d{4}-\d{2}-\d{2}[ T_]\d{2}[-:]\d{2}"), ""),
    (re.compile(r"0x[0-9a-fA-F]+"), "0xHEX"),
    (re.compile(r"coords:\s*-?\d+,\s*-?\d+,\s*-?\d+"), "coords:X,Y,Z"),
    (re.compile(r"\bid=?\s*-?\d+"), "id=N"),
    (re.compile(r":\d+\)"), ":N)"),                     # (Foo.lua:123)
    (re.compile(r"\s+"), " "),
]
INTERESTING = re.compile(r"ERROR|WARN|Exception|Callframe|error", re.I)
SDOC = re.compile(r"SDOC\|(\w+)\|(\d+)\|(.*)")


def signature(line):
    for pattern, repl in NOISE:
        line = pattern.sub(repl, line)
    return line.strip()[:200]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("logfile")
    ap.add_argument("--top", type=int, default=15)
    a = ap.parse_args()

    sigs, examples = Counter(), {}
    mem, calls = [], defaultdict(list)

    with open(a.logfile, errors="replace") as fh:
        for line in fh:
            m = SDOC.search(line)
            if m:
                kind, ts, payload = m.groups()
                if kind == "MEM":
                    kb = float(payload.split("|")[0])
                    mem.append((int(ts), kb))
                elif kind == "CALL":
                    count, label = payload.split("|", 1)
                    calls[label].append(int(count))
                continue
            if INTERESTING.search(line):
                s = signature(line)
                sigs[s] += 1
                examples.setdefault(s, line.rstrip())

    print(f"=== repeated problems ({len(sigs)} distinct) ===")
    for sig, n in sigs.most_common(a.top):
        flag = "  <-- RUNAWAY" if n >= 100 else ""
        print(f"{n:>7}x{flag}\n        {examples[sig][:180]}")

    if mem:
        first_kb, last_kb = mem[0][1], mem[-1][1]
        span_min = (mem[-1][0] - mem[0][0]) / 60000 or 1
        print(f"\n=== lua heap ({len(mem)} samples) ===")
        print(f"  {first_kb:,.0f} KB -> {last_kb:,.0f} KB   "
              f"({(last_kb - first_kb) / span_min:+,.0f} KB/min)")
        if last_kb > first_kb * 1.5:
            print("  LEAK: Lua heap grew >50%. The busiest counter below is the suspect.")

    if calls:
        print("\n=== call counts per minute (max observed) ===")
        for label, series in sorted(calls.items(), key=lambda kv: -max(kv[1]))[:a.top]:
            print(f"{max(series):>9,}  {label}")

    if not sigs and not mem:
        print("nothing matched -- wrong file? try ~/Zomboid/console.txt")


def _selfcheck():
    assert signature("ERROR: Lua f:0 st:26,652,056 at foo coords: 13583, 1299, 0") == \
           signature("ERROR: Lua f:9 st:99,999,999 at foo coords: 1, 2, 0"), "sig must collapse"
    assert signature("ERROR: a") != signature("ERROR: b")
    print("selfcheck ok")


if __name__ == "__main__":
    import sys
    _selfcheck() if "--selfcheck" in sys.argv else main()
