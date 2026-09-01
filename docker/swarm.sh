#!/usr/bin/env bash
# Launch the ucie2-pipe7-bridge DV swarm.
#
# A swarm-manager dispatches one dv-env-tester per DV tier + the infra-agent,
# applies the minimal fixes to get the local gate green, commits to a branch, and
# opens a PR (a human merges; CI validates the heavy --binary UVM + trace_compare
# on the PR). Runs Claude Code NON-bare so .claude/agents/*.md are discovered.
# Portable: CI runner, dev box, or the Docker image. Adapted from the
# axi-on-ucie-to-mem sibling repo. See .claude/agents/*.md and docs/phase_d_swarm.md.
#
# Task source (precedence): $1  >  $SWARM_TASK  >  stdin  >  docker/swarm-task.md
# Inputs: SWARM_MODEL_PROVIDER (anthropic|kimi), GITHUB_TOKEN (branch/commit/PR),
#         GIT_AUTHOR_NAME/EMAIL, SWARM_MAX_PARALLEL, SWARM_PERMISSION_MODE.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=docker/provider-env.sh
. "$SELF_DIR/provider-env.sh"
swarm_resolve_provider || exit $?

# Resolve the repo. On a checkout, use it. The image ships code without .git, so
# clone at run time from GITHUB_TOKEN + slug — that is what lets the manager
# branch/commit/push/open a PR.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$ROOT" ]; then
  repo="${SWARM_REPO:-${GITHUB_REPOSITORY:-markrthomas/ucie2-pipe7-bridge}}"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    ROOT="${SWARM_CLONE_DIR:-/tmp/ucie2-swarm-repo}"
    echo "swarm: no local checkout — cloning ${repo} into ${ROOT}" >&2
    rm -rf "$ROOT"
    git clone --depth 50 "https://x-access-token:${GITHUB_TOKEN}@github.com/${repo}.git" "$ROOT" >&2
  else
    ROOT="/work"
    echo "swarm: no checkout and no GITHUB_TOKEN — running from ${ROOT} (edit/test only, no PR)." >&2
  fi
fi
cd "$ROOT"

task="${1:-}"; [ "$#" -gt 0 ] && shift || true
[ -z "$task" ] && task="${SWARM_TASK:-}"
[ -z "$task" ] && [ ! -t 0 ] && task="$(cat)"
[ -z "$task" ] && [ -f "$ROOT/docker/swarm-task.md" ] && task="$(cat "$ROOT/docker/swarm-task.md")"
[ -z "$task" ] && { echo "swarm: no task (arg / \$SWARM_TASK / stdin / docker/swarm-task.md)" >&2; exit 2; }

git config --global user.name  "${GIT_AUTHOR_NAME:-ucie2 dv swarm}"
git config --global user.email "${GIT_AUTHOR_EMAIL:-ucie2-dv-swarm@users.noreply.github.com}"
git config --global --add safe.directory "$ROOT"
if [ -n "${GITHUB_TOKEN:-}" ]; then
  export GH_TOKEN="$GITHUB_TOKEN"; gh auth setup-git 2>/dev/null || true
else
  echo "swarm: GITHUB_TOKEN not set — swarm will edit & test but cannot push/PR." >&2
fi

# Throttle tester concurrency to available RAM (each Verilator/g++ build can need
# ~2 GB). Override with SWARM_MAX_PARALLEL.
avail_mb="$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 4096)"
if [ -z "${SWARM_MAX_PARALLEL:-}" ]; then
  SWARM_MAX_PARALLEL=$(( avail_mb / 2048 ))
  [ "$SWARM_MAX_PARALLEL" -lt 1 ] && SWARM_MAX_PARALLEL=1
  [ "$SWARM_MAX_PARALLEL" -gt 4 ] && SWARM_MAX_PARALLEL=4
fi
echo "swarm: ~${avail_mb} MB available -> at most ${SWARM_MAX_PARALLEL} dv-env-tester(s) in parallel." >&2

prompt="You are the swarm manager. Use the swarm-manager subagent to carry out the task below, following its documented procedure, then print its final report verbatim.

HOST CAPACITY: ~${avail_mb} MB memory available. Dispatch AT MOST ${SWARM_MAX_PARALLEL} dv-env-tester subagent(s) in parallel; run the tiers in batches of that size.

TASK:
$task"

perm="${SWARM_PERMISSION_MODE:-acceptEdits}"
tools="${SWARM_ALLOWED_TOOLS:-Bash,Read,Edit,Write,Grep,Glob,Task,Agent}"
exec claude -p "$prompt" \
  --permission-mode "$perm" \
  --allowedTools "$tools" \
  --output-format "${CLAUDE_OUTPUT_FORMAT:-text}" \
  "$@"
