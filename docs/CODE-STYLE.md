# ScenesPZ Code Style

Derived from reading Bandits 42.20 (129 Lua files, 22,458 lines) — the most successful
PZ NPC framework on the Workshop. We copy what works there and fix what does not.

## Adopt

**1. One prefix, every global.** Bandits declares ~20 globals, all `Bandit*`. Zero
collision risk in a shared namespace. Ours are all `Scenes*` / `TLOU*`.

**2. Idempotent module header.** Every file opens the same way:

```lua
ScenesFoo = ScenesFoo or {}
```

Re-loading never clobbers state, and load order stops mattering.

**3. AI as a data-driven state machine.** Bandits' best idea. Each behavior is its own
file exposing stages that return a plain table:

```lua
ZombiePrograms.Roadblock.Main = function(bandit)
    local tasks = {}
    ...
    return { status = true, next = "Main", tasks = tasks }
end
```

The stage does not call the next stage — it *names* it. The scheduler drives. New behavior
= new file, zero edits to existing code. This is exactly where our factions plug in.

**4. Tasks are plain serializable data**, never closures:

```lua
local task = { action = "Time", lock = true, anim = "GetUp", time = 150 }
```

Survives the client/server boundary. A closure would not.

**5. Guard clauses over nesting.** 107 of them in Bandits.

```lua
if not square then return end
```

## Fix

**6. Wrap engine calls that can vanish between builds.** Bandits has **zero `pcall` in
22,458 lines**. That is precisely why one removed method — `IsoObject:transmitCompleteItemToServer()`,
gone in 42.20 — turned into 1,553 exceptions in a single session and killed the frame rate.

```lua
-- an engine method disappearing must degrade, not cascade
local ok, err = pcall(function() obj:transmitCompleteItemToClients() end)
if not ok then ScenesDoctor.log("ERR", "transmit failed: " .. tostring(err)) end
```

Do this at engine boundaries. Not on our own pure functions — there it just hides bugs.

**7. Document the contract, not the line.** Bandits is 4.3% comments and the
`{status, next, tasks}` contract is written down nowhere; it has to be reverse-engineered.
Every stage table and every cross-module return shape gets a comment block.

**8. Data belongs in data files.** `BanditUtils.ItemVisuals` is a literal table of item ids
inside a `.lua`. Ours go in `media/scripts/` — declarative content survives game updates,
Lua does not.

**9. One source, thin version folders.** Bandits ships 7 full copies (42.12 … 42.20). The
bug above still exists in 6 of them because fixing one fixes nothing else. We keep shared
code in `common/` and put only genuinely version-specific overrides in `42.x/`.

**10. Package deliberately.** `lua/client/error.txt` in Bandits is a 1,581-line macOS crash
dump that shipped to 933k subscribers. Nothing outside the intended file list goes into
`Contents/`.

## Mechanics

- 4 spaces. `local` by default. Early returns.
- English in code, comments, and commits.
- Lint before every commit: `luajit -bl <file>` (PZ is Lua 5.1). Free, no game required.
- Behind `ScenesDoctor.DEBUG`, `print()` generously — `console.txt` is the only debugger.
