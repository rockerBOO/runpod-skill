# shellcheck shell=bash
# Sourced by the rp-* scripts. Resolves connection details for a pod.
# The SSH port CHANGES on every pod restart, so it is read fresh from `pod get .ssh` on every call.
# Key: ~/.runpod/ssh/runpodctl-ssh-key (override with RP_KEY).
# RP_DIR: this scripts dir (symlinks resolved). RP_STATE: PID files, timer logs and per-pod known_hosts, account-wide like the pods
# (default ~/.runpod/state; never find these processes with pgrep/pkill -f).
# shellcheck disable=SC2034  # RP_DIR / RP_SSH_OPTS are used by the scripts that source this file
RP_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
RP_STATE=${RP_STATE:-$HOME/.runpod/state}
rp_resolve() {
  local pod="$1" info
  [ -n "$pod" ] || { echo "usage: pod id required (see: runpodctl pod list)" >&2; return 2; }
  if [ -z "${RP_HOST:-}" ] || [ -z "${RP_PORT:-}" ]; then
    # `pod get .ssh` is the source of truth (populated within seconds); `ssh info` can stay null on a reachable pod,
    # but its text explains why a pod is not reachable, so it is the fallback.
    info=$(runpodctl pod get "$pod" 2>/dev/null | jq -c '.ssh // {}' 2>/dev/null || true)
    [ -n "$(jq -r '.ip // empty' <<<"$info" 2>/dev/null)" ] || info=$(runpodctl ssh info "$pod" 2>&1 || true)
    RP_HOST=$(jq -r '.ip // empty' <<<"$info" 2>/dev/null || true); RP_PORT=$(jq -r '.port // empty' <<<"$info" 2>/dev/null || true)
    [ -n "$RP_HOST" ] && [ -n "$RP_PORT" ] || { echo "pod $pod not SSH-reachable yet:" >&2; echo "$info" >&2; return 1; }
  fi   # else: manual override from the console (RP_HOST/RP_PORT); set it for one command and one pod only
  RP_KEY=${RP_KEY:-$HOME/.runpod/ssh/runpodctl-ssh-key}
  mkdir -p "$RP_STATE/known_hosts"
  # Runpod reuses ip:port pairs across pods, so keep trust-on-first-use per pod instead of in ~/.ssh/known_hosts.
  RP_SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$RP_STATE/known_hosts/$pod" -o IdentitiesOnly=yes
               -o ConnectTimeout=10 -o ServerAliveInterval=30 -i "$RP_KEY" -p "$RP_PORT")
}
