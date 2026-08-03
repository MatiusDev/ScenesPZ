# Daily dependency drift check

Bandits ships fixes same-day. This timer runs `tools/deps.py check` once a day and fires a
desktop notification only when something drifted — silent otherwise.

```bash
cp tools/systemd/scenespz-deps.* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now scenespz-deps.timer
```

Assumes the repo lives at `~/Docs/Workspace/PZ`; edit `WorkingDirectory` and `ExecStart`
otherwise. Check status with `systemctl --user list-timers scenespz-deps.timer`, last
result with `cat /tmp/scenespz-deps.txt`.
