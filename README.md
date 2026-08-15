# kargo-project-chart

A Helm chart that creates one [Kargo](https://kargo.akuity.io) Project, with its
Warehouses, Stages, and RBAC. Install it once per service.

The chart is published to ECR as an OCI artifact:

```
oci://695434033664.dkr.ecr.us-east-1.amazonaws.com/charts/kargo-project
```

## What one release renders

| Object | Count |
| --- | --- |
| `Namespace` | 1, labelled so Kargo adopts it |
| `Project` + `ProjectConfig` | 1 each, with an auto-promotion policy per stage that opts in |
| `Warehouse` | one per (warehouse, channel) pair |
| `Stage` | one per entry in `stages` |
| RBAC | a `developer` ServiceAccount, and an `approver` one, both optional |

Nothing is hardcoded. The chart ships no default stages, warehouses, or sources —
a consumer supplies all of them.

## Using it

```sh
helm install my-service \
  oci://695434033664.dkr.ecr.us-east-1.amazonaws.com/charts/kargo-project \
  --version 0.1.0 \
  --values my-service.kargo.yaml
```

`helm/kargo-project/values.yaml` documents every field. The fixtures under
`helm/kargo-project/tests/fixtures/` are working examples — start from
`baseline.values.yaml`.

## Channels

The one piece worth reading before you write a values file.

Kargo filters artifacts at the Warehouse subscription. But auto-promotion is a
per-stage policy, and `requestedFreight` selects by freight **origin**, never by
tag. So "auto-promote releases, hand-promote release candidates" cannot be one
Warehouse with two rules — it has to be two origins.

A warehouse listing `channels: [release, rc]` renders one Warehouse per channel
from a single definition, sharing its subscriptions and `updatePaths`. Exactly
one channel is `primary` and keeps the bare warehouse name; the rest get a
`-<channel>` suffix.

The primary rule exists because renaming an origin orphans every stage's freight
history, and each auto-promoting stage then immediately promotes the newest
freight it finds from the new origin. Adopting channels on a live project has to
leave the existing name alone and only add the new ones.

## Development

```sh
just lint          # helm lint against every fixture
just test          # render fixtures, diff against snapshots, check invalid cases
just test-update   # rewrite snapshots after an intentional template change
just render channels
```

The snapshots are the real test. `helm lint` only proves the chart parses; the
snapshots pin warehouse names, the `ctx.targetFreight.origin.name` guards, and
the order of the promotion steps — the parts a consumer's pipeline actually
depends on. Read the diff from `test-update` before committing it.

`tests/invalid/` holds values files that must fail to render, each paired with a
`.expected` substring the error has to contain.

## Releases

Version numbers come from conventional-commit subjects since the last tag, via
`scripts/next-version.sh`. `Chart.yaml` holds a placeholder that CI overwrites
before packaging, so the repo never carries a version that disagrees with what
was published.

- Merge to `main` cuts a stable version, pushes it to ECR, tags it, and creates a
  GitHub release.
- Manual dispatch off any other branch cuts a release candidate: same chart,
  version suffixed `-rc.N`.

While the major version is `0`, a breaking change bumps the minor. Going to
`1.0.0` is a deliberate call.

## Infrastructure

`infra/` holds the ECR repository this chart publishes to, as a Terragrunt unit.
Pull requests plan it, pushes to `main` apply it.

The repository is `IMMUTABLE`: republishing an existing version fails at the
registry rather than silently replacing a chart someone already pulled.

CI assumes the shared `github-actions` role, whose OIDC trust covers
`repo:Fomiller/*:environment:dev`. That is why every job runs in the `dev`
environment — the role will not issue credentials otherwise.
