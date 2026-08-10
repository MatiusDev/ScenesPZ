#!/usr/bin/env python3
"""Mechanical checks that a code review should never have to spend tokens deriving.

Every check here exists because a REAL defect got through. The point is not to replace
`pz-review` -- judgement questions ("does this loop terminate?", "does the caller have a
re-entry motor?") still need a model. The point is that a review should start by running
this and never re-derive what it prints.

    ./tools/audit.py            all checks, whole mod tree
    ./tools/audit.py --diff     only files changed against HEAD
    ./tools/audit.py latches    one check by name

Exit code is 1 if any check reports something that blocks, 0 otherwise. Findings that are
informational (task lifetimes, queue surgery sites) never set the exit code -- they are
context for a reviewer, not verdicts.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD_GLOB = "mods/**/media/lua/**/*.lua"

# The engine decrements task.time once per frame by
#     1 / ((getAverageFPS() + 0.5) * 0.01666667)
# which normalises to ~60 units per real second at any framerate.
#   vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:1802
TIME_UNITS_PER_SECOND = 60.0

# An in-game minute at DayLength 4, measured in play.
EVERY_ONE_MINUTE_SECONDS = 6.0

_TTY = sys.stdout.isatty()
RESET = "\033[0m" if _TTY else ""
DIM = "\033[2m" if _TTY else ""
RED = "\033[31m" if _TTY else ""
YELLOW = "\033[33m" if _TTY else ""
GREEN = "\033[32m" if _TTY else ""


def color(text, c):
    """Wrap in an ANSI code, or return it untouched when this is not a terminal.

    Not cosmetic: the whole point of this tool is that a review pipes its output and reads
    it. Escape sequences leaking into that text is noise a model has to spend tokens
    ignoring."""
    return f"{c}{text}{RESET}"


def lua_files(only_diff):
    if only_diff:
        out = subprocess.run(
            ["git", "diff", "--name-only", "HEAD"],
            cwd=ROOT, capture_output=True, text=True,
        ).stdout.split()
        paths = [ROOT / p for p in out if p.endswith(".lua")]
        return [p for p in paths if p.exists()]
    return sorted(ROOT.glob(MOD_GLOB))


def rel(path):
    return str(path.relative_to(ROOT))


# --- 1. LATCHES ------------------------------------------------------------------------
#
# Four of the six defects a review found on 2026-08-09 were the same shape: a flag written
# onto SR.Mood whose clearing condition either did not exist or could not be guaranteed to
# arrive. `mood.sheltering` re-queued a route forever; `mood.rejoining` left a companion
# unable to fight; `mood.posture` stayed "flee" and suppressed idle.
#
# The rule the project settled on is "an objective is recalculated, never remembered", and
# this is the mechanical half of enforcing it: a flag that is set somewhere and cleared
# nowhere is a latch by construction.

SET_RE = re.compile(r"\bmood\.([A-Za-z_]\w*)\s*=\s*(.+)$")
FALSY = {"nil", "false"}

# THE LINE BETWEEN A LATCH AND A MEASUREMENT, and getting it right is what makes this check
# usable rather than noise. The first version flagged `mood.fear`, `mood.friends` and
# `mood.rung` -- all of which are recomputed unconditionally every sweep and are exactly the
# shape the project WANTS. Flagging them would have taught people to ignore the check.
#
#   DECISION  -- `mood.sheltering = true`, `mood.posture = "flee"`. A remembered verdict. It
#                stays until something clears it, and the thing that clears it is where every
#                latch bug in this project has lived.
#   MEASUREMENT -- `mood.fear = math.max(...)`, `mood.friends = friends`. An expression
#                evaluated from the world each pass. It cannot go stale; the next sweep
#                overwrites it.
#
# So: only a literal constant on the right-hand side counts. That is the mechanical form of
# "an objective is recalculated, never remembered".
LITERAL_RE = re.compile(r"""^(true|\d+(\.\d+)?|"[^"]*"|'[^']*')$""")


def check_latches(files):
    findings = []
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()

        setters, clearers = {}, {}
        for n, line in enumerate(lines, 1):
            code = line.split("--", 1)[0]
            m = SET_RE.search(code)
            if not m:
                continue
            name, rhs = m.group(1), m.group(2).strip().rstrip(",")
            first = rhs.split(",")[0].strip()
            if first in FALSY or rhs in FALSY:
                clearers.setdefault(name, n)
            elif LITERAL_RE.match(first):
                setters.setdefault(name, n)

        # Multiple assignment: `mood.a, mood.b = nil, nil`
        for n, line in enumerate(lines, 1):
            code = line.split("--", 1)[0]
            if "nil" in code and code.count("mood.") > 1 and "=" in code:
                for name in re.findall(r"\bmood\.([A-Za-z_]\w*)", code.split("=")[0]):
                    clearers.setdefault(name, n)

        for name, n in sorted(setters.items(), key=lambda kv: kv[1]):
            if name not in clearers:
                findings.append((rel(path), n,
                                 color(f"mood.{name} is set and NEVER cleared in this file", RED)))
            else:
                # WHY THIS IS LISTED RATHER THAN PASSED OVER, and it is the honest limit of a
                # mechanical check. Every latch that actually broke this project DID have a
                # clear -- `mood.sheltering` had one, `mood.rejoining` had one. They broke
                # because the clear could not be REACHED: it hung off a condition the latch
                # itself suppressed, or off a fear value fed by the zombies the NPC had
                # stopped fighting. No grep decides that.
                #
                # So the tool does what a tool can: it hands over the complete inventory with
                # both line numbers, turning an open-ended hunt into a short checklist. The
                # question to ask at each one is "can this clear be reached while the latch is
                # held?" -- and that question is what a review should be spending tokens on.
                findings.append((rel(path), n,
                                 f"mood.{name}  set here, cleared at :{clearers[name]}  "
                                 f"{DIM}-> can that clear be reached while it is held?{RESET}"))
    return findings, any("NEVER cleared" in f[2] for f in findings)


# --- 2. TASK LIFETIMES -----------------------------------------------------------------
#
# A follow task was queued with `time = 20` and re-checked by a handler throttled to 800 ms.
# The task lives 0.33 s, so by the time the handler looked again it was always gone, and the
# guard built on top of it was dead code that shipped. Nobody caught it by reading, because
# the arithmetic lives in the engine and the constant lives in the mod.
#
# This prints the real number so nobody has to do that division again.

TASK_TIME_RE = re.compile(r"\btime\s*=\s*(\d+)")


def check_task_times(files):
    findings = []
    for path in files:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        for n, line in enumerate(lines, 1):
            code = line.split("--", 1)[0]
            if "action" not in code and "time" not in code:
                continue
            m = TASK_TIME_RE.search(code)
            if not m or "action" not in code:
                continue
            units = int(m.group(1))
            secs = units / TIME_UNITS_PER_SECOND
            note = f"time={units} lives {secs:.2f}s"
            if secs < 1.0:
                note += "  <- shorter than one second; anything polling slower will never see it"
            findings.append((rel(path), n, note))
    return findings, False


# --- 3. QUEUE SURGERY ------------------------------------------------------------------
#
# `Bandit.ClearTasks` wipes the queue and is the reason secondary objectives cannot survive.
# `Bandit.AddTaskFirst` pre-empts the head AND flushes the WHOLE queue past 9 entries,
# ignoring `task.lock` -- Bandit.lua:304 -- so it can silently discard Die, Zombify and GetUp.
# Neither fact is visible at the call site. This lists every site so a review can see the
# whole surface at once instead of grepping for it.

QUEUE_CALLS = ("Bandit.ClearTasks", "Bandit.AddTaskFirst", "Bandit.RemoveTask",
               "Bandit.UpdateTask", "brain.tasks =")


def check_queue_surgery(files):
    findings = []
    for path in files:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        for n, line in enumerate(lines, 1):
            code = line.split("--", 1)[0]
            for call in QUEUE_CALLS:
                if call in code:
                    findings.append((rel(path), n, f"{call.strip()}  {DIM}{code.strip()[:70]}{RESET}"))
    return findings, False


# --- 4. VENDOR CITATIONS ---------------------------------------------------------------
#
# vendor/Bandits ships 42.12 through 42.20 side by side and the game loads only the folder
# matching its build. A file:line citation without the version folder is ambiguous at best
# and wrong at worst: GetAccessSquare moved 17 lines between 42.18 and 42.20.

VENDOR_CITE_RE = re.compile(r"vendor/(Bandits|TheArk|WeekOne)[\w./]*")
VERSION_RE = re.compile(r"/\d+\.\d+/")


def check_vendor_citations(files):
    findings = []
    for path in files:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        for n, line in enumerate(lines, 1):
            for m in VENDOR_CITE_RE.finditer(line):
                cite = m.group(0)
                if not VERSION_RE.search(cite) and not cite.rstrip("/").endswith(m.group(1)):
                    findings.append((rel(path), n, f"vendor citation without a version folder: {cite}"))
    return findings, True


# --- 5. SWALLOWED ERRORS ---------------------------------------------------------------
#
# The bag bug hid for two sessions because `pcall` returned true -- the inner function had
# merely returned early -- so even the "will not render" line never printed. A pcall whose
# failure is neither returned nor logged cannot be debugged from console.txt, which is the
# only instrument this project has for client code.

PCALL_RE = re.compile(r"\bpcall\s*\(")


def check_swallowed_pcalls(files):
    findings = []
    for path in files:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        for n, line in enumerate(lines, 1):
            code = line.split("--", 1)[0]
            if not PCALL_RE.search(code):
                continue
            # Assigned results are inspected somewhere; bare `pcall(...)` is not.
            if re.match(r"\s*(local\s+)?[\w.,\s]+=\s*pcall", code.strip()):
                continue
            if re.match(r"\s*(local\s+)?[\w.,\s]+=\s*.*\bpcall", code.strip()):
                continue
            findings.append((rel(path), n,
                             "pcall result is discarded -- a failure here leaves no trace in console.txt"))
    return findings, False


# --- 6. LUACHECK -----------------------------------------------------------------------
#
# A `local` declared BELOW a function that reads it is invisible to it and silently becomes
# a nil global. luac compiles it happily. That exact mistake made WANTS[task.want] an index
# into nil and threw every time an NPC finished searching a container.


def check_luacheck(files):
    probe = subprocess.run(["which", "luacheck"], capture_output=True, text=True)
    if probe.returncode != 0:
        return [("-", 0, "luacheck is NOT installed -- the nil-global trap is unchecked. "
                         "Install: luarocks install luacheck")], False

    findings = []
    for path in files:
        out = subprocess.run(
            ["luacheck", "--no-color", "--codes", "--globals", "getCell", "--", str(path)],
            capture_output=True, text=True,
        ).stdout
        for line in out.splitlines():
            m = re.match(r"\s*(\S+):(\d+):\d+:\s*(.+)", line)
            if m and ("W113" in m.group(3) or "undefined" in m.group(3)):
                findings.append((rel(path), int(m.group(2)), m.group(3)))
    return findings, False


CHECKS = {
    "latches": ("flags set but never cleared", check_latches),
    "tasktime": ("real lifetime of every queued task", check_task_times),
    "queue": ("every place the task queue is operated on", check_queue_surgery),
    "vendor": ("vendor citations missing a version folder", check_vendor_citations),
    "pcall": ("pcall results that are discarded", check_swallowed_pcalls),
    "luacheck": ("undefined globals and lexical-scope traps", check_luacheck),
}


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("check", nargs="?", choices=sorted(CHECKS), help="run only this check")
    ap.add_argument("--diff", action="store_true", help="only files changed against HEAD")
    args = ap.parse_args()

    files = lua_files(args.diff)
    if not files:
        print("no lua files to audit")
        return 0

    selected = {args.check: CHECKS[args.check]} if args.check else CHECKS
    blocked = False

    for name, (title, fn) in selected.items():
        findings, blocks = fn(files)
        head = f"== {name} -- {title} =="
        if not findings:
            print(f"{head}\n  {color('none', GREEN)}\n")
            continue

        tag = color("BLOCKS", RED) if blocks else color("info", YELLOW)
        print(f"{head}  [{tag}]")
        for path, line, msg in findings:
            where = f"{path}:{line}" if line else path
            print(f"  {where}: {msg}")
        print()
        if blocks:
            blocked = True

    print(color("== audit FAILED ==", RED) if blocked else color("== audit clean ==", GREEN))
    return 1 if blocked else 0


if __name__ == "__main__":
    sys.exit(main())
