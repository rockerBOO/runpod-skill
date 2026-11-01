---
name: runpod-checkin
description: Use when a Runpod pod is running a paid job and a monitor wakes up, a heartbeat fires, the user asks how a job is going, or a session is about to end; also when starting a background monitor or safety timer for a pod.
---

# Runpod check-ins, timers and monitors

Nothing on Runpod enforces a runtime or budget limit; a job that finishes into an interactive prompt keeps billing silently. Scripts: the runpod skill's `scripts/` directory, i.e. `S=<this skill's base dir>/../runpod/scripts` (`$S/rp-status`, `$S/rp-ssh`, `$S/rp-timer`). State: `${RP_STATE:-$HOME/.runpod/state}`.

## At every check-in

1. `$S/rp-status`. Exit 0 = OK, 1 = warnings (listed with `!!`), 2 = Runpod API unreadable (status unknown: say so, don't assume fine).
2. **Evaluate every active job, not just the one that woke you:** progress, best-so-far result, elapsed cost vs. the approved Max budget/Max runtime (read them from the run log), and whether anything idles at a prompt (idle = billed).
3. Probe real state: `$S/rp-ssh <pod> 'tmux capture-pane -pt <session> | tail -20; tail -n 20 <log>'`. A matched log string doesn't prove success, and a prompt drawn to the terminal never reaches the log; "log not growing" is a signal.
4. Write the check-in (numbers) to the run log, then report numbers to the user, not "healthy".
5. Before ending a session: `rp-status`, and tell the user what still bills.

## Safety timer (immediately after `pod create`)

```bash
$S/rp-timer arm <pod> <max-runtime-secs> [logfile]   # tell the user the printed wall-clock fire time
$S/rp-timer status ; $S/rp-timer cancel <pod>
```
`pod stop` (not delete) when pod uptime reaches the max; retries and logs each attempt. Runs **locally**: the pod-side API key can't stop the pod and `kill 1` inside it doesn't either. A suspend delays it until wake; a power-off loses it.

## Monitors

Start with the Bash tool's `run_in_background` (a plain `&` never wakes the agent, so check-ins silently slip). Example: exits on done, on failure, or after a 45-min heartbeat, and removes its PID file only on done so `rp-status` doesn't warn on success:

```bash
bash -c 'st=${RP_STATE:-$HOME/.runpod/state}/monitors; mkdir -p "$st"; pidf=$st/<name>.pid; echo $$ > "$pidf"
  while sleep 60; do
    out=$(<S>/rp-ssh <pod> "tail -n 200 <log>" 2>&1) || { echo "ssh failed: $out"; continue; }
    grep -q "<done-pattern>" <<<"$out" && { echo DONE; rm -f "$pidf"; exit 0; }
    grep -qE "Traceback|Error|Killed" <<<"$out" && { echo FAILED; tail -5 <<<"$out"; exit 1; }
    [ $SECONDS -gt 2700 ] && { echo HEARTBEAT; exit 0; }
  done'
```
- Confirm after launch and at every check-in: `kill -0 $(cat <state>/monitors/<name>.pid)`. Relaunch after a heartbeat.
- **PIDs live in files, never in `pgrep -f`/`pkill -f`**: those match the agent's own shell (its command line contains the pod id) and kill it.

## Warnings

| `rp-status` warning | Action |
|---|---|
| no live safety timer | `rp-timer arm` now; tell the user the fire time |
| monitor DEAD while a pod runs | Relaunch (`run_in_background`), or remove its PID file if that run is done |
| log not updated for N min | Stalled, at a prompt, or crashed: inspect the tmux pane |
| cannot SSH | `runpodctl pod get <id> \| jq 'del(.env)'`, `runpodctl pod logs <id>` |
| ERROR state / network volumes listed | Can still bill; report to the user |
