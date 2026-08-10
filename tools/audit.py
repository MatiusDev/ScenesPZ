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


# Java-bound globals that do not match any harvest pattern: lowercase, or called bare rather
# than as `Namespace.thing`. Short list on purpose -- every addition here is a name we are
# asserting exists, which is exactly the claim R1 says to verify. All of these appear
# hundreds of times in pzserver/media/lua.
ENGINE_EXTRAS = ["instanceof", "ZombRand", "ZombRandFloat", "getText", "print"]


def gen_globals():
    """Rebuild .luacheckrc by harvesting the real global namespace.

    Hand-writing this list was the obvious approach and it is the wrong one: PZ and Bandits
    expose their whole API as globals, the list runs to thousands of names, and a curated
    copy would be stale within a week. Harvesting it from pzserver/media/lua (the engine,
    authoritative for 42.20), vendor/, and our own tree means it cannot drift.

    What survives the allowlist is the finding worth having: a name defined NOWHERE. That is
    the trap that killed a whole behaviour on 08-08 -- a `local` declared below the function
    that reads it is invisible to it and becomes a nil global, and luac compiles it silently.
    """
    names = set()

    def scan(base, engine):
        count = 0
        for p in base.rglob("*.lua"):
            try:
                txt = p.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            count += 1
            names.update(re.findall(r"^([A-Za-z_]\w*)\s*=", txt, re.M))
            names.update(re.findall(r"^function\s+([A-Za-z_]\w*)[.:(]", txt, re.M))
            if engine:
                names.update(re.findall(r"\b(get[A-Z]\w*)\s*\(", txt))
                names.update(re.findall(r"\b(is[A-Z]\w*)\s*\(", txt))
                names.update(re.findall(r"\b([A-Z][A-Za-z0-9]{2,})\s*[.:]", txt))
        return count

    engine_n = scan(ROOT / "pzserver" / "media" / "lua", True)
    vendor_n = scan(ROOT / "vendor", True)
    ours_n = scan(ROOT / "mods", False)
    names.update(ENGINE_EXTRAS)
    names = sorted(n for n in names if len(n) > 1 and not n.startswith("_"))

    body = "\n".join('    "%s",' % n for n in names if '"' not in n)
    (ROOT / ".luacheckrc").write_text(
        f'''-- GENERATED by `./tools/audit.py --gen-globals`. Do not hand-edit.
--
-- {len(names)} names harvested from pzserver/media/lua ({engine_n} files, the engine and the
-- authoritative reference for build 42.20), vendor/ ({vendor_n}) and mods/ ({ours_n}).
--
-- Without this, a bare luacheck run reports several hundred false positives -- PZ and Bandits
-- expose their entire API as Lua globals -- and a check that cries wolf teaches people to
-- ignore it. With it, what remains is a name defined NOWHERE, which is the shape of the trap
-- that killed a whole behaviour on 08-08.

std = "lua51"
max_line_length = false
self = false

-- Unused named constants stay documented in place in this project, deliberately.
ignore = {{ "212", "213", "611", "612", "614", "631" }}

read_globals = {{
{body}
}}
''', encoding="utf-8")
    return len(names)


def check_luacheck(files):
    probe = subprocess.run(["which", "luacheck"], capture_output=True, text=True)
    if probe.returncode != 0:
        return [("-", 0, "luacheck is NOT installed -- the nil-global trap is unchecked. "
                         "Install on Arch: sudo pacman -S luacheck")], False
    if not (ROOT / ".luacheckrc").exists():
        return [("-", 0, "no .luacheckrc -- run ./tools/audit.py --gen-globals first")], False

    findings = []
    for path in files:
        out = subprocess.run(
            ["luacheck", "--no-color", "--codes", "--", str(path)],
            cwd=ROOT,
            capture_output=True, text=True,
        ).stdout
        for line in out.splitlines():
            m = re.match(r"\s*(\S+):(\d+):\d+:\s*(.+)", line)
            if m and ("W113" in m.group(3) or "W211" in m.group(3)):
                findings.append((rel(path), int(m.group(2)), m.group(3)))
    return findings, False


# --- 7. LUA 5.2+ SYNTAX -----------------------------------------------------------------
#
# The engine runs Kahlua, which is Lua 5.1. The `luac` on this machine is 5.5, and it happily
# compiles syntax 5.1 never had -- so `tools/lint.sh` reports "ok" for code that throws in game,
# on another machine, where the only symptom is a stack trace in console.txt.
#
# Found the hard way: a `goto continue` passed lint and would have failed in play.
#
# Only forms that are unambiguous in Lua source are checked. Bitwise operators are deliberately
# absent -- `~` is also 5.1's "not equals" when written `~=`, and `&`/`|` appear inside string
# patterns often enough that flagging them would be noise.

FIVETWO = [
    (re.compile(r"\bgoto\s+[A-Za-z_]\w*"), "goto -- 5.2+, Kahlua is 5.1"),
    (re.compile(r"::[A-Za-z_]\w*::"), "goto label -- 5.2+, Kahlua is 5.1"),
    (re.compile(r"[^/]//[^/]"), "integer division // -- 5.3+, Kahlua is 5.1"),
    (re.compile(r"\btable\.(pack|unpack)\b"), "table.pack/unpack -- 5.2+; 5.1 has bare unpack()"),
    (re.compile(r"\bmath\.type\b"), "math.type -- 5.3+, Kahlua is 5.1"),
]


def check_five_one(files):
    findings = []
    for path in files:
        for n, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            code = line.split("--", 1)[0]
            if not code.strip():
                continue
            for rx, msg in FIVETWO:
                if rx.search(code):
                    findings.append((rel(path), n, color(msg, RED)))
    return findings, True


CHECKS = {
    "latches": ("flags set but never cleared", check_latches),
    "tasktime": ("real lifetime of every queued task", check_task_times),
    "queue": ("every place the task queue is operated on", check_queue_surgery),
    "vendor": ("vendor citations missing a version folder", check_vendor_citations),
    "pcall": ("pcall results that are discarded", check_swallowed_pcalls),
    "luacheck": ("undefined globals and lexical-scope traps", check_luacheck),
    "lua51": ("syntax the engine's Lua 5.1 does not have", check_five_one),
}


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("check", nargs="?", choices=sorted(CHECKS), help="run only this check")
    ap.add_argument("--diff", action="store_true", help="only files changed against HEAD")
    ap.add_argument("--gen-globals", action="store_true",
                    help="rebuild .luacheckrc from the engine, vendor and mod trees")
    args = ap.parse_args()

    if args.gen_globals:
        print(f"wrote .luacheckrc with {gen_globals()} harvested globals")
        return 0

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
