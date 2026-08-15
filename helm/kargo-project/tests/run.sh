#!/usr/bin/env bash
# Render every fixture and diff it against its committed snapshot, then check that each
# invalid fixture fails to render with the expected message.
#
#   ./run.sh              check
#   ./run.sh --update     rewrite the snapshots from the current chart
#
# `helm lint` only proves the chart renders. These snapshots are what pin the parts a
# consumer actually depends on: warehouse names (freight origins), the
# `ctx.targetFreight.origin.name` guards, and the order of the promotion steps.
set -euo pipefail

cd "$(dirname "$0")"
chart=".."
update=0
[[ "${1:-}" == "--update" ]] && update=1

fail=0
diffout="$(mktemp)"
trap 'rm -f "$diffout"' EXIT

# Helm patch releases have changed where they emit blank lines around document
# separators, which broke these snapshots for no real reason. Nothing in the
# rendered output uses a blank line meaningfully, so drop them on both sides.
normalize() { grep -v '^[[:space:]]*$' || true; }

for fixture in fixtures/*.values.yaml; do
  name="$(basename "$fixture" .values.yaml)"
  snapshot="snapshots/${name}.yaml"
  rendered="$(helm template "$name" "$chart" --values "$fixture")"

  if [[ "$update" == 1 ]]; then
    mkdir -p snapshots
    printf '%s\n' "$rendered" > "$snapshot"
    echo "updated $snapshot"
    continue
  fi

  if [[ ! -f "$snapshot" ]]; then
    echo "FAIL $name: no snapshot at $snapshot (run ./run.sh --update)" >&2
    fail=1
    continue
  fi

  if diff -u <(normalize < "$snapshot") <(printf '%s\n' "$rendered" | normalize) > "$diffout"; then
    echo "ok   $name"
  else
    echo "FAIL $name: render does not match $snapshot" >&2
    cat "$diffout" >&2
    fail=1
  fi
done

[[ "$update" == 1 ]] && exit 0

# Each invalid/<name>.values.yaml pairs with invalid/<name>.expected — a substring the
# template's `fail` message must contain.
for fixture in invalid/*.values.yaml; do
  [[ -e "$fixture" ]] || break
  name="$(basename "$fixture" .values.yaml)"
  expected="$(cat "invalid/${name}.expected")"

  if output="$(helm template "$name" "$chart" --values "$fixture" 2>&1)"; then
    echo "FAIL $name: expected the render to fail, but it succeeded" >&2
    fail=1
  elif [[ "$output" != *"$expected"* ]]; then
    echo "FAIL $name: error did not mention '$expected'" >&2
    echo "$output" >&2
    fail=1
  else
    echo "ok   $name (rejected)"
  fi
done

exit "$fail"
