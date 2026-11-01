# runpod-skill

Claude Code skills for renting, running jobs on, monitoring and tearing down [Runpod](https://runpod.io) GPU pods with `runpodctl` v2+.

| Skill | Loads when |
|---|---|
| `skills/runpod` | Any Runpod pod/volume work. Hard rules (approval before spend, no deletes without asking, secrets, timers), workflow, plan template, helper scripts in `scripts/`, CLI notes in `reference.md` |
| `skills/runpod-checkin` | A paid job is running: check-ins, `rp-status`, safety timers, background monitors |
| `skills/runpod-python-env` | Installing Python deps on a pod without losing the image's CUDA torch |

## Install

```bash
./install.sh              # symlinks each skill into ~/.claude/skills (edits here are live)
```
Or install the repo as a Claude Code plugin (`.claude-plugin/plugin.json`). Pick one: doing both gives duplicate skills.

Requirements: Linux (GNU coreutils `date -d`, `realpath`, `setsid`), `runpodctl` v2+, `jq`, `ssh`, `rsync`, `bash`; a passphrase-less SSH key on the Runpod account (default `~/.runpod/ssh/runpodctl-ssh-key`).

## Developing

- Scripts must stay job-agnostic: jobs plug in via arguments (pod id, commands), not edits.
- Scripts find each other via `realpath`, so they can be symlinked into a project (e.g. `ln -s ../runpod-skill/skills/runpod/scripts scripts`).
- Runtime state (timer/monitor PIDs) lives in `$RP_STATE` (default `~/.runpod/state`), never in the repo.
- Keep `SKILL.md` files short; put detail in `reference.md`.
