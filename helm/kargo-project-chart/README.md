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
| image | `.Digest` | none — see below |
| chart | `.Version` | `attribute` |
| git | `.Tag` | `attribute`, e.g. `ID` for the commit SHA |

Image sources write a digest, not a tag, because a mutable tag lets the cluster
drift off the freight that was actually promoted. A stage can set
`digestPinnedImages: true` to write `<tag>@<digest>` instead, which only makes
sense when the consuming chart renders the value as `repository:<value>`.

## Two ways to keep prereleases out of a stage

**Channels** keep prerelease freight out of the stage's origin entirely. Quieter,
and the one to reach for first.

**`blockPrerelease`** is a `fail` step inside the promotion. It fires after the
freight has already been selected, so an auto-promoting stage records a failed
Promotion for every prerelease it sees. Use it as the backstop for a stage fed by
a warehouse that isn't channelized.

They compose. A gated stage reading only the release channel is belt and braces.

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
