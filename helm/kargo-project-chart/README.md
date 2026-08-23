# kargo-project-chart

Creates a Kargo Project, its Warehouses, its Stages, and project RBAC.

`values.yaml` is the reference — every field is documented there, next to the
field itself. This file covers the model, not the individual keys.

## The model

Four lists, and they are deliberately separate.

**Sources** — `services`, `charts`, `gitRepos`. Each entry is a name plus where
the artifact lives. Nothing else. A source does not know where its version gets
written or which stage consumes it.

**Warehouses** — subscribe to sources, emit freight, and declare where that
freight is written (`updatePaths`). Path mappings live here rather than on the
stage, which is what keeps stage definitions from growing as services and files
pile up.

**Stages** — thin environment bindings. Which warehouses feed them, which branch
and overlay they write, which Argo CD app to sync. A stage stays about five lines
no matter how many files its warehouse touches.

Source names are the join key: `updates[].source` names a source, and the chart
resolves it to an image, chart, or git source on its own. Names must be unique
across all three source lists — the chart fails the render if they are not.

## What each source kind writes

| Kind | Written by default | Override |
| --- | --- | --- |
| image | `<tag>@<digest>` | none — see below |
| chart | `.Version` | `attribute` |
| git | `.Tag` | `attribute`, e.g. `ID` for the commit SHA |

Image sources carry a digest, never a bare tag, because a mutable tag lets the
cluster drift off the freight that was actually promoted. They carry the tag
too, because `sha256:cff4894…` tells you nothing in `kubectl describe`.

`<tag>@<digest>` belongs in a key the chart renders as `repository:<value>`. A
stage whose chart renders `repository@<value>` sets `digestPinnedImages: false`
to get a bare `sha256:...` back. Name the key for what it holds — `image.tag`
when pinned, `image.digest` when bare.

## Two ways to keep prereleases out of a stage

**Channels** keep prerelease freight out of the stage's origin entirely. Quieter,
and the one to reach for first.

**`blockPrerelease`** is a `fail` step inside the promotion. It fires after the
freight has already been selected, so an auto-promoting stage records a failed
Promotion for every prerelease it sees. Use it as the backstop for a stage fed by
a warehouse that isn't channelized.

They compose. A gated stage reading only the release channel is belt and braces.

## Credentials

Kargo reads a project's credentials from the project's own namespace, not from
the control-plane namespace, and finds them by the `kargo.akuity.io/cred-type`
label.

**A project writes nothing about them.** Which GitHub account, which registry,
which secret store — those are facts about the cluster, not about the service.
They are defined once in this chart's `values.yaml` and every project gets the
same three: `git`, `ecr-image`, `ecr-chart`. Each becomes one ExternalSecret
named `kargo-<key>-credentials`.

The chart never holds a credential, only the reference to where the cluster
keeps one.

A project overrides only when it genuinely differs. Helm merges the entry, so
naming one field keeps the rest:

```yaml
credentials:
  # No chart subscription, so no helm credential.
  ecr-chart:
    enabled: false
  # Git lives somewhere the cluster default does not match.
  git:
    repoURL: '^https://git\.example\.com/widget/.*$'
```

Inside an entry, `data` values are Go templates over whatever the store
returns. Name the keys with `remoteKeys` (secret key to remote key), or pull a
whole entry with `dataFrom`.

Two things bite here:

- `repoURL` is compared for **equality** unless `repoURLIsRegex` is true. A
  prefix with the flag off matches nothing, and the request goes out
  unauthenticated — which surfaces as "no tags found", not as an auth error.
- Kargo looks up each cred-type **independently**. An `image` credential does
  not authenticate a chart subscription against the same registry; that needs a
  second entry with `type: helm`.

## Validation

The chart fails the render, rather than producing objects that look fine and
misbehave later, when:

- a source name is reused across `services`, `charts`, or `gitRepos`
- a warehouse names a channel not defined in `channels`
- a warehouse declares more than one primary channel
- a warehouse sets both `channels` and `allowTagsRegex`
- a stage names a warehouse or an upstream stage that does not exist
- a stage sets `channel` on a warehouse that declares none, or names a channel
  that warehouse does not render
- `updates[].source` names a source that does not exist
- an image source's update sets `attribute` to anything but `Digest`
