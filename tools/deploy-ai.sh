#!/usr/bin/env bash
# Configure AI secrets and redeploy the Alfaeq AI edge functions.
#
# Required environment:
#   SUPABASE_ACCESS_TOKEN  Supabase personal access token (sbp_...)
#   PROJECT_REF            Supabase project reference (the subdomain of *.supabase.co)
#
# Provider secrets (at least one complete set) are read from .env.ai (git-ignored):
#   AI_BASE_URL, AI_API_KEY, AI_MODEL         (preferred, OpenAI-compatible)
#   UNSLOTH_BASE_URL, UNSLOTH_API_KEY, UNSLOTH_MODEL
#   OPENAI_BASE_URL, OPENAI_API_KEY, OPENAI_MODEL
#   OPENHANDS_API_KEY                         (agent execution via developer-control)
#   TYPESAFE_API_KEY                          (optional, Jev event classification)
#   ALFAEQ_SHEETS_SYNC_SECRET                 (optional, Sheets sync)
#
# Usage:
#   SUPABASE_ACCESS_TOKEN=... PROJECT_REF=... tools/deploy-ai.sh
#
# Never commit .env.ai. This script never prints secret values.
set -u

SUPABASE_BIN="${SUPABASE_BIN:-/workspace/supabase_cli/node_modules/.bin/supabase}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${SUPABASE_ACCESS_TOKEN:-}" ]; then echo "ERROR: SUPABASE_ACCESS_TOKEN is required." >&2; exit 1; fi
if [ -z "${PROJECT_REF:-}" ]; then echo "ERROR: PROJECT_REF is required." >&2; exit 1; fi

if [ -f "$ROOT/.env.ai" ]; then
  # shellcheck disable=SC1091
  set -a; . "$ROOT/.env.ai"; set +a
fi

# Collect any provider secrets that are present (names only are reported).
SECRETS=()
for name in AI_BASE_URL AI_API_KEY AI_MODEL \
            UNSLOTH_BASE_URL UNSLOTH_API_KEY UNSLOTH_MODEL \
            OPENAI_BASE_URL OPENAI_API_KEY OPENAI_MODEL \
            OPENHANDS_API_KEY OPENHANDS_BASE_URL \
            TYPESAFE_API_KEY TYPESAFE_ENDPOINT TYPESAFE_MODEL \
            ALFAEQ_SHEETS_SYNC_SECRET; do
  val="${!name:-}"
  if [ -n "$val" ]; then SECRETS+=("$name=$val"); fi
done

if [ "${#SECRETS[@]}" -eq 0 ]; then
  echo "ERROR: no provider secrets found. Create .env.ai (see header) or export them." >&2
  exit 1
fi

echo "Setting ${#SECRETS[@]} secret(s) on project."
"$SUPABASE_BIN" secrets set "${SECRETS[@]}" --project-ref "$PROJECT_REF" >/dev/null || {
  echo "ERROR: failed to set secrets." >&2; exit 1; }
echo "Secrets set."

FUNCTIONS=(ai-gateway developer-control ai-event-worker sheets-catalog-sync)
for fn in "${FUNCTIONS[@]}"; do
  echo "Deploying $fn ..."
  "$SUPABASE_BIN" functions deploy "$fn" --project-ref "$PROJECT_REF" --use-api >/dev/null || {
    echo "ERROR: failed to deploy $fn." >&2; exit 1; }
  echo "Deployed $fn."
done

echo "Done. Verify with:"
echo "  curl -s -X POST \"https://\$PROJECT_REF.supabase.co/functions/v1/ai-gateway\" \\"
echo "    -H \"Authorization: Bearer <user-jwt>\" -H 'Content-Type: application/json' \\"
echo "    -d '{\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}'"
