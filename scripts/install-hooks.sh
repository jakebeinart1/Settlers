#!/usr/bin/env bash
#
# Install the pre-push hook that runs scripts/gate.sh.
#
# Run once per clone:  ./scripts/install-hooks.sh
#
# WHY AN INSTALLER AND NOT core.hooksPath. Either works; this writes a real
# .git/hooks/pre-push so that `ls .git/hooks` tells the truth about what is
# armed. Two of Alex's five repos have hook *configuration* checked in and no
# hook actually installed - Reelty's main branch sat red for 33 days on two
# auto-fixable lint rules that its own uninstalled pre-commit hook would have
# fixed. Config that is not installed is not a gate.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path hooks/pre-push)"

mkdir -p "$(dirname "$HOOK")"

cat > "$HOOK" <<'HOOK_BODY'
#!/usr/bin/env bash
#
# Refuses the push if scripts/gate.sh is red. Installed by scripts/install-hooks.sh.
#
# Bypass deliberately with:  git push --no-verify
# (If you find yourself doing that routinely, the gate is wrong - fix the gate.)

set -uo pipefail

# Hooks are shared by linked worktrees. Git invokes pre-push from the checkout
# being pushed, so resolve that checkout rather than the hook's main .git path.
REPO_ROOT="$(git rev-parse --show-toplevel)"

# Git streams "<local ref> <local sha> <remote ref> <remote sha>" lines on stdin
# and expects the hook to consume them. If the hook exits without reading, git
# writes into a closed pipe, takes SIGPIPE, and `git push` returns 141 AFTER the
# gate has printed every gate green - a push that looks like it passed and
# leaves origin unchanged. Drain stdin first, and use the range for the secret
# scan while we have it.
RANGE=""
while read -r _local_ref local_sha _remote_ref remote_sha; do
  if [[ "$remote_sha" =~ ^0+$ ]]; then
    RANGE=""                       # new branch: no useful range, scan everything
  else
    RANGE="$remote_sha..$local_sha"
  fi
done

echo "pre-push: running scripts/gate.sh"
if [[ -n "$RANGE" ]]; then
  "$REPO_ROOT/scripts/gate.sh" --range "$RANGE"
else
  "$REPO_ROOT/scripts/gate.sh"
fi
status=$?

if [[ $status -ne 0 ]]; then
  echo ""
  echo "pre-push: REFUSED - the gate is red. Fix it, or push with --no-verify if you"
  echo "          know why that is the right call."
fi
exit $status
HOOK_BODY

chmod +x "$HOOK"
echo "installed: $HOOK"
echo "verify with: ls -l .git/hooks/pre-push"
