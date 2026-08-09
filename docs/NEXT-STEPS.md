# Superseded

This file was a project-state snapshot from 2026-08-03. It is kept only so that links to it
do not break, and it should not be read for anything.

It went stale badly enough to be a trap: it recorded that ScenesRelations had never been run
in game, and it asserted that a relation record must live on the entity because
`BanditUtils.GetCharacterID` "identifies an outfit, not an individual". Both are now known
to be wrong -- the id is per person, and the record lives in sharded global ModData
precisely because the entity does not survive a cell unload.

**Read instead:**

- `docs/PLAN-STATUS.md` -- where the project is, and an index to everything else. Start here.
- `docs/TESTING-NOW.md` -- what to test in game right now.
- `docs/TEST-LOG.md` -- what every past round proved.
- `docs/plans/README.md` -- the staged roadmap.
- `docs/CAPABILITY-MAP.md` -- engine questions already settled, with their evidence.
- `docs/TODO.md` -- observations from play that no stage has claimed yet.
