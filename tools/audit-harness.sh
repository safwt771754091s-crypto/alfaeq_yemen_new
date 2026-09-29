#!/usr/bin/env bash
set -euo pipefail
fail=0
check(){ if [ -e "$1" ]; then echo "[PASS] $1"; else echo "[FAIL] $1"; fail=1; fi; }
check AGENTS.md
check feature_list.json
check progress.md
check session-handoff.md
if grep -q "flutter analyze" AGENTS.md; then echo "[PASS] verification documented"; else echo "[FAIL] verification documented"; fail=1; fi
if grep -q "Supabase" AGENTS.md; then echo "[PASS] production backend constraint documented"; else echo "[FAIL] production backend constraint documented"; fail=1; fi
exit $fail
