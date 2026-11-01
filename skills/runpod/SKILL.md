---
name: runpod
description: Use when choosing, pricing, renting, connecting to, running jobs on, monitoring, or tearing down Runpod GPU pods or network volumes with runpodctl, or when a task (training, fine-tuning, inference, evals) needs a cloud GPU and Runpod is the provider.
---

# Runpod GPU pods

Renting costs real money and deleting is permanent, so the rules come before convenience. Scripts: `scripts/` next to this file (call by full path; a project may symlink it as `scripts/`). CLI detail, sizing method, gotchas and common mistakes: `reference.md`.

## Hard rules

1. **No spend without approval.** Before `pod create` / `network-volume create`, present the plan below and wait for an explicit yes for *that* plan. Approval for one pod does not cover the next.
2. **Choose hardware by tradeoffs** (`reference.md` → Sizing a workload), never by reflex (cheapest, or "a good GPU"). Decide alone only when one option clearly fits; otherwise put the options to the user. Out of stock means come back with options; any change of GPU, tier or price needs approval.
3. **Never delete data without asking.** Delete only after outputs are verified off the pod and the user confirms. "Stop it" is ambiguous: ask stop (volume kept, still billed) or delete.
4. **Secrets:** never print tokens (`RUNPOD_API_KEY`, `HF_TOKEN`, `~/.runpod/config.toml`, `.env`). `pod get` includes `env`: always `runpodctl pod get <id> | jq 'del(.env)'`.
5. **Never use sudo.** Install to `~/.local/bin`; on the pod you are root.
6. **On failure, report the exact error and ask.** No workarounds that change the method.
7. **Safety timer immediately after `pod create` returns**, before anything that can hang. Tell the user the wall-clock fire time.
8. **Stopped is not free.** End every session with `rp-status` and tell the user what still bills (pods, stopped volumes, network volumes).
9. **"Noted" means written to a file first** (the project's run log, else `/tmp/<job>_run.log`); name the file. Log commands, decisions and costs.

## Workflow

1. `runpodctl version` (v2+), `runpodctl me` (balance, spend limit).
2. Size the workload and compare candidates from `runpodctl gpu list`.
3. Present the plan; wait for yes.
4. `runpodctl pod create ... --ports "22/tcp" --volume-in-gb N --name <job>`. Its output may not be valid JSON (multi-key `PUBLIC_KEY`); get the id with `runpodctl pod list | jq -r '.[] | select(.name=="<job>") | .id'` and never fall back to printing the raw output. Capacity error → see `reference.md` (retrying the same GPU/tier/price in another datacenter is fine). Auto-mode blocks create → ask the user to run it with `! runpodctl ...`.
5. `rp-timer arm <pod> <max-runtime-secs from the plan> [log]` (default log `$RP_STATE/timers/<pod>.log`; passing the run log puts stop attempts there).
6. `rp-up <pod> [--hf-token]`.
7. `rp-sync` code, verify with `rp-ssh <pod> ls`; run long jobs in `tmux`, logging to `/workspace/*.log`. Python deps: **REQUIRED SUB-SKILL** runpod-python-env.
8. While it runs: **REQUIRED SUB-SKILL** runpod-checkin.
9. Teardown: outputs verified off-pod → user picks stop/delete → `rp-timer cancel` → delete `/workspace/hf/token` if streamed → `rp-status` shows nothing unexpected → report runtime and cost.

## Plan template

```
Job:            <what and why>
GPU:            <gpuId> x<count>, <VRAM> GB, <Secure|Community>, <datacenter or any>, $<x>/hr (gpu list)
Why this GPU:   <requirements it meets; comparable workloads + sources; optimizations assumed>
Options:        <top 2-4: $/hr | est. pace & runtime | est. total | headroom/risk>; open tradeoffs for the user
Disks:          container <n> GB, volume <n> GB at /workspace (or network volume <id>)
Image:          <...>
Est. runtime:   <h>   Est. cost: $<x>   Max runtime: <h>   Max budget: $<x>
Secrets needed: <names only>
Outputs go to:  <HF repo / path>   Teardown: <stop|delete> after user confirms
```

## Scripts (take the pod id; SSH details re-read every call)

| Script | Purpose |
|---|---|
| `rp-timer arm\|status\|cancel` | Local hard-stop timer (`pod stop`, not delete), logs to `$RP_STATE/timers/<pod>.log` |
| `rp-up <pod> [--hf-token]` | Wait for SSH; install tmux/rsync/git/uv (nothing else into the image's Python); with `--hf-token` (user's OK only) stream `HF_TOKEN` from `$RP_ENV_FILE`/`./.env` to `/workspace/hf/token` |
| `rp-ssh <pod> [cmd]` | Shell or one-off command (stdin passes through) |
| `rp-sync <pod> <local> [remote]` / `--pull <remote> <local>` | rsync; dir pushes skip `.git .venv __pycache__ *.safetensors` |
| `rp-status` | Pods, timers, monitors, volumes, money; exit 1 = warnings, 2 = API unreadable |
| `rp-logs <pod> [file\|--tmux\|--container]` | For humans (never returns). Agents: `rp-ssh <pod> 'tail -n 50 <log>'` |

Env: `RP_STATE` (default `~/.runpod/state`), `RP_KEY` (default `~/.runpod/ssh/runpodctl-ssh-key`), `RP_ENV_FILE`, `RP_HOST`/`RP_PORT` (one-pod manual override).
