# shellcheck shell=bash
# Resolve the model provider for a headless Claude Code swarm run. Sourced (not
# exec'd) by docker/swarm.sh. Adapted from the axi-on-ucie-to-mem sibling repo.
#
# SWARM_MODEL_PROVIDER selects the vendor the agents' opus/sonnet/haiku tier
# aliases resolve to for the WHOLE run (Claude Code's provider is process-wide):
#   anthropic (default)  Claude via ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN.
#   kimi                 Kimi K3 via Moonshot's Anthropic-compatible endpoint
#                        (KIMI_API_KEY). See the IP/compliance caution below.
#
# swarm_resolve_provider sets SWARM_PROVIDER (normalized) and returns non-zero if
# the selected provider's credential is missing.

swarm_resolve_provider() {
  # Strip whitespace/newlines from pasted keys (a trailing newline copied into a
  # CI/Railway secret field otherwise yields a spurious "401 API key invalid").
  for v in ANTHROPIC_API_KEY KIMI_API_KEY CLAUDE_CODE_OAUTH_TOKEN; do
    if [ -n "${!v:-}" ]; then printf -v "$v" '%s' "$(printf '%s' "${!v}" | tr -d '[:space:]')"; export "$v"; fi
  done
  # A subscription OAuth token (sk-ant-oat…, from `claude setup-token`) pasted into
  # ANTHROPIC_API_KEY is rejected by the Messages API — reroute it.
  case "${ANTHROPIC_API_KEY:-}" in
    sk-ant-oat*)
      CLAUDE_CODE_OAUTH_TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:-$ANTHROPIC_API_KEY}"; export CLAUDE_CODE_OAUTH_TOKEN
      unset ANTHROPIC_API_KEY
      echo "provider(anthropic): ANTHROPIC_API_KEY held an OAuth token — rerouting to CLAUDE_CODE_OAUTH_TOKEN." >&2 ;;
  esac

  SWARM_PROVIDER="${SWARM_MODEL_PROVIDER:-anthropic}"
  case "$SWARM_PROVIDER" in
    anthropic)
      if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        echo "provider: anthropic (Console API key)" >&2
      elif [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
        unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN 2>/dev/null || true
        echo "provider: anthropic (subscription OAuth token)" >&2
      else
        echo "provider(anthropic): no credential — set ANTHROPIC_API_KEY (sk-ant-api…) or" >&2
        echo "  CLAUDE_CODE_OAUTH_TOKEN (sk-ant-oat…, from 'claude setup-token')." >&2
        return 3
      fi
      # Pin the tier aliases so selection is deterministic, not the account default.
      #   opus  = manager (deep agentic reasoning, fixes, git/PR)
      #   sonnet= infra-agent (well-scoped Dockerfile/CI/script edits)
      #   haiku = dv-env-testers (fan out in parallel, run+report; cheap/fast)
      export ANTHROPIC_DEFAULT_OPUS_MODEL="${ANTHROPIC_OPUS_MODEL:-claude-opus-5}"
      export ANTHROPIC_DEFAULT_SONNET_MODEL="${ANTHROPIC_SONNET_MODEL:-claude-sonnet-5}"
      export ANTHROPIC_DEFAULT_HAIKU_MODEL="${ANTHROPIC_HAIKU_MODEL:-claude-haiku-4-5}"
      echo "provider: anthropic (opus=${ANTHROPIC_DEFAULT_OPUS_MODEL}, sonnet=${ANTHROPIC_DEFAULT_SONNET_MODEL}, haiku=${ANTHROPIC_DEFAULT_HAIKU_MODEL})" >&2 ;;
    kimi)
      [ -z "${KIMI_API_KEY:-}" ] && { echo "provider(kimi): KIMI_API_KEY not set." >&2; return 3; }
      export ANTHROPIC_BASE_URL="${ANTHROPIC_BASE_URL:-https://api.moonshot.ai/anthropic}"
      export ANTHROPIC_AUTH_TOKEN="$KIMI_API_KEY"; unset ANTHROPIC_API_KEY
      export ANTHROPIC_DEFAULT_OPUS_MODEL="${KIMI_OPUS_MODEL:-kimi-k3}"
      export ANTHROPIC_DEFAULT_SONNET_MODEL="${KIMI_SONNET_MODEL:-kimi-k2.7-code}"
      export ANTHROPIC_DEFAULT_HAIKU_MODEL="${KIMI_HAIKU_MODEL:-kimi-k2.7-code-highspeed}"
      echo "provider: kimi -> ${ANTHROPIC_BASE_URL}" >&2
      echo "  ⚠ IP/COMPLIANCE: this sends repo contents to a China-based provider. Do NOT use" >&2
      echo "    for export-sensitive IP; verify Moonshot is not Entity/SDN-listed first." >&2 ;;
    *) echo "provider: unknown SWARM_MODEL_PROVIDER='$SWARM_PROVIDER' (want anthropic|kimi)." >&2; return 4 ;;
  esac
  return 0
}
