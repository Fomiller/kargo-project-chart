#!/usr/bin/env bash
# Exercise next-version.sh against a throwaway repo, one case per line.
#
# The version logic has no other coverage, and it is the piece that decides what
# gets published — a wrong bump is only visible after it has been pushed to a
# registry that refuses to take the version back.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/next-version.sh"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT

cd "$DIR"
git init -q
git config user.email test@example.com
git config user.name test

fail=0
check() {
  local want="$1" got="$2" label="$3"
  if [[ "$want" == "$got" ]]; then
    echo "ok   $label -> $got"
  else
    echo "FAIL $label: want $want, got $got" >&2
    fail=1
  fi
}

commit() { git commit -q --allow-empty -m "$1"; }

commit "chore: init"
check "0.1.0" "$($SCRIPT)" "no tags"

git tag v0.1.0
commit "fix: a bug"
check "0.1.1" "$($SCRIPT)" "fix after 0.1.0"

commit "feat: a feature"
check "0.2.0" "$($SCRIPT)" "feat wins over fix"

commit "feat(scope)!: breaking"
check "0.2.0" "$($SCRIPT)" "breaking pre-1.0 bumps minor, not major"

check "0.2.0-rc.1" "$($SCRIPT --rc)" "first rc"
git tag v0.2.0-rc.1
check "0.2.0-rc.2" "$($SCRIPT --rc)" "second rc"
check "0.2.0" "$($SCRIPT)" "rc tags do not become the base"

git tag v1.0.0
commit "fix: post 1.0"
check "1.0.1" "$($SCRIPT)" "patch after 1.0.0"

commit "feat!: breaking post 1.0"
check "2.0.0" "$($SCRIPT)" "breaking post-1.0 bumps major"

commit "chore: body break

BREAKING CHANGE: yes"
check "2.0.0" "$($SCRIPT)" "BREAKING CHANGE in body"

exit "$fail"
