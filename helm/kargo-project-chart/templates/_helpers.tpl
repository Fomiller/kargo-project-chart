{{/*
The Kargo Project name, which is also its namespace. Kargo requires the two to
match, so this is the single place either is spelled.
*/}}
{{- define "kargo-project-chart.namespace" -}}
{{- required "project.name is required" .Values.project.name -}}
{{- end -}}

{{/*
Turn a source name into a valid Kargo promotion-template var identifier holding
that source's URL. Hyphens become underscores so the result is referenceable as
`vars.<name>` inside a Kargo expression.

  "my-service" -> "image_my_service"
*/}}
{{- define "kargo-project-chart.imageVar" -}}
image_{{ . | replace "-" "_" }}
{{- end -}}

{{- define "kargo-project-chart.chartVar" -}}
chart_{{ . | replace "-" "_" }}
{{- end -}}

{{- define "kargo-project-chart.gitVar" -}}
git_{{ . | replace "-" "_" }}
{{- end -}}

{{/*
The Kargo Warehouse name a (warehouse, channel) pair renders as — i.e. the
freight ORIGIN name.

The primary channel renders under the bare warehouse name. That is deliberate:
renaming an origin orphans a stage's freight history and makes every
auto-promoting stage immediately promote the newest freight from the new origin.
So adopting channels on a live project has to leave the existing name alone and
only ADD the non-primary ones.

Input: dict with `base` (warehouse name), `channel` (may be ""), and `channels`
(.Values.channels).
*/}}
{{- define "kargo-project-chart.warehouseName" -}}
{{- $chan := .channel | default "" -}}
{{- $def := dict -}}
{{- if hasKey .channels $chan -}}{{- $def = index .channels $chan -}}{{- end -}}
{{- if or (eq $chan "") $def.primary -}}
{{- .base -}}
{{- else -}}
{{- printf "%s-%s" .base $chan -}}
{{- end -}}
{{- end -}}

{{/*
The freight origin a stage reads from a given warehouse — that warehouse's
rendered name for the channel the stage selected. Validates the pairing, since a
stage naming a channel its warehouse doesn't render would silently request
freight from an origin that does not exist.

Input: dict with `root` ($), `stage`, and `warehouse` (the warehouse object).
*/}}
{{- define "kargo-project-chart.stageOrigin" -}}
{{- $channels := .root.Values.channels | default dict -}}
{{- $wh := .warehouse -}}
{{- $whChannels := $wh.channels | default list -}}
{{- $stageChan := .stage.channel | default "" -}}
{{- if not $whChannels -}}
  {{- if $stageChan -}}
    {{- fail (printf "stage %q sets channel %q, but warehouse %q declares no channels" .stage.name $stageChan $wh.name) -}}
  {{- end -}}
  {{- $wh.name -}}
{{- else -}}
  {{- $chan := $stageChan -}}
  {{- if not $chan -}}
    {{- range $whChannels -}}
      {{- if hasKey $channels . -}}
        {{- if (index $channels .).primary -}}{{- $chan = . -}}{{- end -}}
      {{- end -}}
    {{- end -}}
    {{- if not $chan -}}
      {{- fail (printf "warehouse %q declares channels %v but none is primary, so stage %q must set `channel`" $wh.name $whChannels .stage.name) -}}
    {{- end -}}
  {{- else if not (has $chan $whChannels) -}}
    {{- fail (printf "stage %q requests channel %q from warehouse %q, which only declares %v" .stage.name $chan $wh.name $whChannels) -}}
  {{- end -}}
  {{- include "kargo-project-chart.warehouseName" (dict "base" $wh.name "channel" $chan "channels" $channels) -}}
{{- end -}}
{{- end -}}

{{/*
Resolve the sources a warehouse subscribes to for one kind. A subscription field
is either the literal string "all" or a list of source names; anything else
subscribes to none.

Input: dict with `selector` (the warehouse's field) and `all` (the matching
.Values list). Output: the selected subset, in .Values order.
*/}}
{{- define "kargo-project-chart.selectSources" -}}
{{- $selected := list -}}
{{- $all := .all | default list -}}
{{- if kindIs "slice" .selector -}}
  {{- range .selector -}}
    {{- $name := . -}}
    {{- range $all -}}
      {{- if eq .name $name -}}{{- $selected = append $selected . -}}{{- end -}}
    {{- end -}}
  {{- end -}}
{{- else if and (kindIs "string" .selector) (eq .selector "all") -}}
  {{- $selected = $all -}}
{{- end -}}
{{- $selected | toJson -}}
{{- end -}}

{{/*
The Kargo expression resolving a source's human-readable tag or version. This is
what the prerelease gate matches against, so it is deliberately the TAG for image
sources rather than the digest the yaml-update writes.

Input: dict with `root` ($), `source` (name), and `origin` (rendered warehouse
name). Output: an expression string, without the surrounding delimiters.
*/}}
{{- define "kargo-project-chart.versionExpr" -}}
{{- $src := .source -}}
{{- $origin := .origin -}}
{{- $found := "" -}}
{{- range .root.Values.services -}}
  {{- if eq .name $src -}}
    {{- $found = printf "imageFrom(vars.%s, warehouse('%s')).Tag" (include "kargo-project-chart.imageVar" $src) $origin -}}
  {{- end -}}
{{- end -}}
{{- range .root.Values.charts -}}
  {{- if eq .name $src -}}
    {{- if .chart.name -}}
      {{- $found = printf "chartFrom(vars.%s, '%s', warehouse('%s')).Version" (include "kargo-project-chart.chartVar" $src) .chart.name $origin -}}
    {{- else -}}
      {{- $found = printf "chartFrom(vars.%s, warehouse('%s')).Version" (include "kargo-project-chart.chartVar" $src) $origin -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- range .root.Values.gitRepos -}}
  {{- if eq .name $src -}}
    {{- $found = printf "commitFrom(vars.%s, warehouse('%s')).Tag" (include "kargo-project-chart.gitVar" $src) $origin -}}
  {{- end -}}
{{- end -}}
{{- if not $found -}}
{{- fail (printf "source %q is not defined in services[], charts[], or gitRepos[]" $src) -}}
{{- end -}}
{{- $found -}}
{{- end -}}

{{/*
The Kargo expression a yaml-update step writes for one source. Distinct from
versionExpr because what gets written is not what gets gated: an image source
writes its DIGEST, since a mutable tag would leave the cluster free to drift off
the freight that was actually promoted.

Input: dict with `root` ($), `source` (name), `origin` (rendered warehouse name),
`stage`, and `attribute` (may be empty).
*/}}
{{- define "kargo-project-chart.updateExpr" -}}
{{- $src := .source -}}
{{- $origin := .origin -}}
{{- $attr := .attribute | default "" -}}
{{- $found := "" -}}
{{- range .root.Values.services -}}
  {{- if eq .name $src -}}
    {{- if and $attr (ne $attr "Digest") -}}
      {{- fail (printf "updatePaths: image source %q sets attribute %q; image sources only support \"Digest\"" $src $attr) -}}
    {{- end -}}
    {{- $var := include "kargo-project-chart.imageVar" $src -}}
    {{- /* `ne ... false` rather than `default true`, because Helm's `default`
           returns its fallback for any empty value and `false` is empty — a
           stage that deliberately opted out would silently get `true` back. */ -}}
    {{- if ne $.stage.digestPinnedImages false -}}
      {{- $found = printf "imageFrom(vars.%s, warehouse('%s')).Tag + '@' + imageFrom(vars.%s, warehouse('%s')).Digest" $var $origin $var $origin -}}
    {{- else -}}
      {{- $found = printf "imageFrom(vars.%s, warehouse('%s')).Digest" $var $origin -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- range .root.Values.charts -}}
  {{- if eq .name $src -}}
    {{- $var := include "kargo-project-chart.chartVar" $src -}}
    {{- if .chart.name -}}
      {{- $found = printf "chartFrom(vars.%s, '%s', warehouse('%s')).%s" $var .chart.name $origin ($attr | default "Version") -}}
    {{- else -}}
      {{- $found = printf "chartFrom(vars.%s, warehouse('%s')).%s" $var $origin ($attr | default "Version") -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- range .root.Values.gitRepos -}}
  {{- if eq .name $src -}}
    {{- $found = printf "commitFrom(vars.%s, warehouse('%s')).%s" (include "kargo-project-chart.gitVar" $src) $origin ($attr | default "Tag") -}}
  {{- end -}}
{{- end -}}
{{- if not $found -}}
{{- fail (printf "updatePaths: source %q is not defined in services[], charts[], or gitRepos[]" $src) -}}
{{- end -}}
{{- $found -}}
{{- end -}}
