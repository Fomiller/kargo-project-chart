chart := "helm/kargo-project-chart"
infraDir := "infra/live/dev"

default:
    @just --list

# Lint the chart against every fixture. The shipped values are all empty, so
# linting those alone proves almost nothing.
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    for fixture in {{chart}}/tests/fixtures/*.values.yaml; do
        echo "== $(basename "$fixture")"
        helm lint {{chart}} --values "$fixture"
    done

test:
    {{chart}}/tests/run.sh
    scripts/tests/next-version.test.sh

# Rewrite the snapshots from the current templates. Read the diff before
# committing it — that diff is the whole point of the snapshots.
test-update:
    {{chart}}/tests/run.sh --update

# Render one fixture to stdout, e.g. `just render channels`.
render fixture="baseline":
    helm template {{fixture}} {{chart}} --values {{chart}}/tests/fixtures/{{fixture}}.values.yaml

version:
    @scripts/next-version.sh

plan:
    terragrunt --non-interactive stack run --tf-path terraform --working-dir {{infraDir}} -- plan

apply:
    terragrunt --non-interactive stack run --tf-path terraform --working-dir {{infraDir}} -- apply

clean:
    find . -name "_.*.gen.tf" -type f -delete
    find . -name ".terragrunt-cache" -type d -prune -exec rm -rf {} +
    rm -rf dist
