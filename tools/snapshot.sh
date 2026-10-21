#!/usr/bin/env bash
# Alfaeq Yemen — local snapshot helper.
#
# Saves a recoverable, timestamped copy of the current working tree into a
# git ref under refs/snapshots/ and writes a dated Arabic/English note to
# docs/releases/SNAPSHOTS.md. Snapshots are local-only (never pushed) and
# survive branch switches, so any change can be rolled back.
#
# Usage:
#   tools/snapshot.sh [label] [--note "explanation"]
#
# Recover a snapshot:
#   git checkout <ref> -- .            # restore the tree
#   git show <ref>:path/to/file        # inspect a single file
#   git diff HEAD <ref>                # compare

set -u

label="snapshot"
if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then
  label="$1"
  shift
fi
note=""
while [ $# -gt 0 ]; do
  case "$1" in
    --note) note="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

root="$(git rev-parse --show-toplevel)"
cd "$root" || exit 1

ts="$(date -u +%Y%m%dT%H%M%SZ)"
safe="$(printf '%s' "$label" | tr -c 'A-Za-z0-9._-' '-')"
ref="refs/snapshots/${ts}-${safe}"

# Include the working tree exactly as it is, including uncommitted edits.
git add -A >/dev/null 2>&1
tree="$(git write-tree)"
head="$(git rev-parse HEAD 2>/dev/null || echo none)"
parent=""
[ "$head" != "none" ] && parent="-p $head"

commit="$(git commit-tree "$tree" $parent -m "snapshot ${ts}: ${label}")"
git update-ref "$ref" "$commit"

# Log inside .git so the working tree stays clean and no snapshot ever
# dirties the next commit.
log="$(git rev-parse --git-dir)/alfaeq-snapshots.log"
stamp="$(date -u '+%Y-%m-%d %H:%M UTC')"
{
  echo "${stamp} | ${label} | ${ref} | ${commit} | base ${head}"
  if [ -n "$note" ]; then
    echo "    note: ${note}"
  fi
} >> "$log"

# Unstage so the working tree is left as it was found.
git reset -q >/dev/null 2>&1 || true

echo "Snapshot saved: ${ref}"
echo "Recover with: git checkout ${ref} -- ."
echo "Log: ${log}"
