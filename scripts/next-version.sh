#!/usr/bin/env bash
# Print the next chart version, derived from conventional-commit subjects since
# the last release tag. Prints the version alone, so callers can capture it.
#
#   ./next-version.sh          next stable, e.g. 0.3.0
#   ./next-version.sh --rc     next release candidate, e.g. 0.3.0-rc.2
#
# Bump rules, highest match wins:
#   breaking  `<type>!:` in the subject, or `BREAKING CHANGE` in the body
#   minor     a `feat` commit
#   patch     anything else
#
# While the major version is still 0 a breaking change bumps the MINOR, not the
# major. Going to 1.0.0 is a deliberate call, not something a `!` should trigger.
#
# Release candidates are numbered per target version: the first rc for 0.3.0 is
# 0.3.0-rc.1, and it keeps counting up until 0.3.0 itself is cut.
set -euo pipefail

rc=0
[[ "${1:-}" == "--rc" ]] && rc=1

tag_prefix="v"

last_tag="$(git tag --list "${tag_prefix}*" --sort=-v:refname | grep -v -- '-rc\.' | head -1 || true)"

if [[ -z "$last_tag" ]]; then
  # No release yet. Chart.yaml's committed placeholder is the starting point.
  next="0.1.0"
else
  base="${last_tag#"$tag_prefix"}"
  IFS='.' read -r major minor patch <<< "$base"

  bump="patch"
  while IFS= read -r subject; do
    [[ -z "$subject" ]] && continue
    if [[ "$subject" =~ ^[a-zA-Z]+(\([^\)]*\))?!: ]]; then
      bump="major"
      break
    fi
    if [[ "$subject" =~ ^feat(\([^\)]*\))?: ]]; then
      bump="minor"
    fi
  done < <(git log --format='%s' "${last_tag}..HEAD")

  if git log --format='%B' "${last_tag}..HEAD" | grep -q 'BREAKING CHANGE'; then
    bump="major"
  fi

  case "$bump" in
    major)
      if [[ "$major" == "0" ]]; then
        next="0.$((minor + 1)).0"
      else
        next="$((major + 1)).0.0"
      fi
      ;;
    minor) next="${major}.$((minor + 1)).0" ;;
    patch) next="${major}.${minor}.$((patch + 1))" ;;
  esac
fi

if [[ "$rc" == 1 ]]; then
  n=1
  while git rev-parse -q --verify "refs/tags/${tag_prefix}${next}-rc.${n}" >/dev/null; do
    n=$((n + 1))
  done
  next="${next}-rc.${n}"
fi

printf '%s\n' "$next"
