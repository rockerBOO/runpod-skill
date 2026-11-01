# runpodctl reference and gotchas

`runpodctl <cmd> --help` is authoritative for flags on the installed version. Docs index: https://docs.runpod.io/llms.txt (CLI: https://docs.runpod.io/runpodctl/overview.md). Runpod is spelled with one capital letter.

## CLI versions

| | v1.x (legacy) | v2+ / v3 (current) |
|---|---|---|
| List pods | `runpodctl get pod` | `runpodctl pod list` |
| List GPUs | `runpodctl get cloud` | `runpodctl gpu list` |
| Create | `runpodctl create pod --gpuType ...` | `runpodctl pod create --gpu-id ...` |
| Delete | `runpodctl remove pod` | `runpodctl pod delete` |

v1 `get cloud` shows "Reserved" for every price, so it is useless for price discovery. Upgrade without sudo: download from https://github.com/runpod/runpodctl/releases, verify against `checksums_<ver>_sha256.txt`, `install -m 755 runpodctl-linux-amd64 ~/.local/bin/runpodctl`. (The `cli.runpod.io` install script has returned nothing.) Every pod ships its own `runpodctl` and a pod-scoped API key.

## One-time setup

```bash
runpodctl doctor            # interactive: API key + SSH key + verification
runpodctl me                # clientBalance, currentSpendPerHr, spendLimit
runpodctl ssh list-keys
ssh-keygen -t ed25519 -N "" -f ~/.runpod/ssh/runpodctl-ssh-key      # passphrase-less agent key
runpodctl ssh add-key --key-file ~/.runpod/ssh/runpodctl-ssh-key.pub
```
The key must be on the account **before** creating a pod. Pods get account keys injected via `PUBLIC_KEY`. For an already-running pod: `pod update <id> --env '{"PUBLIC_KEY":"<pubkey>"}'` then `pod restart <id>`. `ssh-keygen -y -f <key>` prompts if the key is encrypted (agents can't use those). `ssh info` reports `ssh_key.exists: false` until the local key file exists (local check only).

## Finding what is available

```bash
runpodctl gpu list [--include-unavailable]
runpodctl datacenter list                 # dc IDs like US-GA-1, per-GPU stock
runpodctl template list --type official ; runpodctl template search pytorch ; runpodctl template get <id>
runpodctl network-volume list ; runpodctl pod list --all ; runpodctl billing pods
runpodctl gpu list | jq -r '.[] | select(.memoryInGb>=24) | [.gpuId,.memoryInGb,.stockStatus,.securePricePerHr,.communityPricePerHr]|@tsv' | sort -t$'\t' -k4 -n | column -t -s$'\t'
```
- `gpuId` is the exact quoted string for `--gpu-id` (e.g. `"NVIDIA A40"`). Prices are null if a tier isn't offered. Confirm `costPerHr` on the pod after creation.
- `stockStatus` is a snapshot; creation can still fail on capacity with `400 There are no longer any instances available with the requested specifications`. Retry pinned to a datacenter that lists the GPU (`gpu list` → `.dataCenterAvailability`, then `pod create ... --data-center-ids <dc>`). Same GPU, tier and price in another datacenter is not a fallback (unless a network volume or region matters); anything else needs approval.
- Pod `uptimeSeconds` can lag wall clock by ~2 min after create; `currentSpendPerHr` from `me` lags ~1 min after a delete.
- Aliases: `tpl`, `nv` (network-volume), `dc`, `sls`, `reg`, `me`.

## Sizing a workload (before proposing a GPU)

Starting estimates, not rules: bf16 weights ≈ 2 bytes/param (9B ≈ 18 GB); add 20–30 % for inference and much more for training (optimizer state, activations). Rough tiers: 24 GB (RTX 4090/3090/A5000/L4), 48 GB (A40/RTX A6000/L40S/RTX 6000 Ada), 80–96 GB (A100/H100/RTX PRO 6000), larger (H200/B200). Secure Cloud is the reliable default for public-IP SSH (needed for rsync). Community Cloud is much cheaper and has given working public-IP SSH, but a given host may lack a public IP; check `pod get .ssh` and be ready to delete and re-plan. Offer it as a tradeoff.

1. **Characterize it.** Model and architecture, parameter count, precision (bf16/fp16/fp8/int4), batch and sequence length, training vs. inference vs. search, single or multi-GPU. Is it compute-bound (training, big batches) or memory-bandwidth-bound (decoding, small batches)? How long does it run, and is there interactive or idle time?
2. **Look for known comparable workloads.** The tool's README/docs hardware notes, its issues, model cards, published benchmarks, and the project's own records of earlier runs, if any. Write down where each number came from.
3. **Consider optimizations that change what you need.** Quantization (8/4-bit), bf16 vs. fp32, LoRA/QLoRA vs. full fine-tune, gradient checkpointing, batch-size tuning, flash/SDPA attention, `torch.compile`, a serving engine (vLLM, SGLang) for inference, CPU offload. Use one only if the tool supports it and it doesn't change the method the user asked for (rule 5). Otherwise offer it as an option.
4. **Check compatibility.** Blackwell (RTX 50xx/PRO, B200) needs CUDA 12.8+ builds. Also check fp8/bf16 support, the image's CUDA vs. `--min-cuda-version`, and whether the tool's kernels (flash-attn, bitsandbytes) build for that architecture.
5. **Estimate each candidate.** Expected pace (it/s, tokens/s, trials/min) → runtime → total cost = runtime × $/hr + setup overhead + disk. A pricier but faster GPU often costs less in total. Include the risk: low stock, Community host without a public IP, little VRAM headroom.
6. **Pilot when it's uncertain.** For long or expensive runs with no good comparable, propose a short paid pilot to measure pace on the cheapest plausible GPU, then extrapolate before committing to the full run.
7. **Present the comparison** (a table of the top 2–4 options: $/hr, est. runtime, est. total, headroom, risks, sources). Recommend one if it clearly wins; otherwise ask the user to choose the tradeoff.

## Creating a pod

```bash
runpodctl pod create \
  --image "runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04" \
  --gpu-id "NVIDIA A40" --gpu-count 1 \
  --container-disk-in-gb 50 --volume-in-gb 100 \
  --ports "22/tcp,8888/http" --name myjob
```
Flags: `--template-id`, `--container-disk-in-gb` (default 20, wiped on stop), `--volume-in-gb` (persistent `/workspace`), `--network-volume-id` (instead of `--volume-in-gb`; pins the datacenter, so pick dc by stock first; 10–4096 GB), `--cloud-type SECURE|COMMUNITY`, `--data-center-ids`, `--min-cuda-version`, `--env`, `--docker-args`.

- Models, datasets, `HF_HOME`, outputs on `/workspace`. Without a volume, `/workspace` is the 20 GB overlay and is wiped on stop.
- Size disks for model + HF cache + outputs.
- Always `--name`.
- `pod create --wait` has returned without a usable result in the past (v3 help now describes a banner check with `--wait-timeout`; re-test before relying on it). Default: create without it and poll `pod get`.
- `pod get` output includes the pod's `env`; filter it (`jq 'del(.env)'`) whenever output may be shown or logged.
- The `/workspace` volume refuses `chown`: `rsync -a` exits 23 even though files arrive (`rp-sync` avoids owner/group). Pip/uv hardlinks fail across filesystems there; set `UV_LINK_MODE=copy`.

## Readiness and connecting

```bash
until [ -n "$(runpodctl pod get <id> | jq -r '.ssh.ip // empty')" ]; do sleep 3; done
runpodctl pod get <id> | jq -r '.ssh.ssh_command'
```
- `runtimeStatus`: `running`, `initializing` (keep polling), `stopped`, `terminated`, `error` (stop polling, read `pod logs`). `pod list` can show `initializing` for a running pod; use `pod get`.
- `.ssh` from `pod get` is the source of truth; `ssh info` is only useful for its explanation text when `.ssh` is empty.
- Basic (proxied) SSH does not support scp/sftp/rsync. Full SSH needs a public IP and `22/tcp` published (Secure Cloud reliably; Community when the host has one).
- Adding a port: `pod update <id> --ports <existing>,22/tcp` **replaces** the list and may restart the container. Checkpoint first.
- HTTP ports: `https://<pod-id>-<port>.proxy.runpod.net`.
- Stock `runpod/pytorch` lacks rsync and tmux; `rp-up`/`rp-sync` install them.
- `pod logs <id>` shows the boot log; first stop when SSH misbehaves. Jobs run in tmux don't appear there.
- From zsh one-liners, `$OPTS` word-splitting breaks ssh; use bash arrays (as the scripts do).

## Secrets on a pod

A new pod has **no** `HF_TOKEN`; its only credential is a pod-scoped `RUNPOD_API_KEY` that can't manage the pod. Tokens get onto a pod by Runpod's normal means, set up by the user: a **Runpod secret** created in the console and referenced at create (`--env '{"HF_TOKEN":"{{ RUNPOD_SECRET_<name> }}"}'`; documented for templates, unverified with `pod create`), or the user logging in on the pod themselves. Agents never copy tokens from local files to a pod; if a job needs one, ask the user to provide it.

## Lifecycle

```bash
runpodctl pod list [--all] ; runpodctl pod get <id> [--include-machine]
runpodctl pod stop <id>      # keeps volume (still billed), drops container disk
runpodctl pod start <id> ; runpodctl pod restart <id> ; runpodctl pod update <id> ...
runpodctl pod delete <id>    # destroys pod + volume. Ask first.
```

## Other

- Serverless: `runpodctl sls` with `template create --serverless`. Read docs first.
- Private images: `runpodctl registry list`, then `--registry-auth-id`.
- Troubleshooting: zero GPUs after restart (https://docs.runpod.io/pods/troubleshooting/zero-gpus.md), 502s (https://docs.runpod.io/pods/troubleshooting/troubleshooting-502-errors.md).

## Common mistakes

| Mistake | Reality |
|---|---|
| Using v1 commands (`get pod`, `create pod`) | v2+ is `pod list`, `pod create`, `gpu list` |
| Treating `running` as SSH-ready | Poll `pod get <id> \| jq .ssh`; `ssh info` can stay null on a reachable pod |
| Caching the SSH port | It changes on every restart; the scripts re-read it |
| `Host key verification failed` | Runpod reuses ip:port across pods; the scripts keep known_hosts per pod in `$RP_STATE/known_hosts/` |
| `Permission denied (publickey)` read as key-injection failure | Usually a passphrase-protected key; agents need a passphrase-less key |
| On-pod watchdog / `kill 1` to cap cost | The pod-side key can't stop the pod and `kill 1` doesn't; the timer must run locally |
| `pgrep -f`/`pkill -f <pod>` | Matches and kills the agent's own shell; use PID files in `$RP_STATE` |
| Timer armed after `rp-up` | `rp-up` can wait ~7 min for SSH while billing; arm right after create |
| `uv sync` / `pip install` on the pod | Pulls a CPU torch; see runpod-python-env |
| Raw `runpodctl pod get` in logs | Prints `env` (secrets); filter with `jq 'del(.env)'` |
| "Stop it" taken as delete | Ask which: stop keeps (and bills) the volume, delete destroys it |
