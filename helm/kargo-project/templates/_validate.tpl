{{/*
Whole-values checks that aren't natural to any one template. Called once from
project.yaml so a bad values file fails on render rather than producing objects
that look fine and misbehave in the cluster.

Renders nothing.
*/}}
{{- define "kargo-project.validate" -}}
{{- $channels := .Values.channels | default dict -}}

{{- /* Source names key the `updates[].source` lookup, so a name reused across
       two kinds would silently resolve to whichever the chart checked first. */ -}}
{{- $seen := dict -}}
{{- range concat (.Values.services | default list) (.Values.charts | default list) (.Values.gitRepos | default list) -}}
  {{- if hasKey $seen .name -}}
    {{- fail (printf "source name %q is used more than once; names must be unique across services[], charts[], and gitRepos[]" .name) -}}
  {{- end -}}
  {{- $_ := set $seen .name true -}}
{{- end -}}

{{- range .Values.warehouses -}}
  {{- $wh := . -}}
  {{- $primaries := list -}}
  {{- range $wh.channels | default list -}}
    {{- if not (hasKey $channels .) -}}
      {{- fail (printf "warehouse %q declares channel %q, which is not defined in .Values.channels" $wh.name .) -}}
    {{- end -}}
    {{- if (index $channels .).primary -}}
      {{- $primaries = append $primaries . -}}
    {{- end -}}
  {{- end -}}
  {{- if gt (len $primaries) 1 -}}
    {{- fail (printf "warehouse %q declares more than one primary channel (%v); only one channel may render under the bare warehouse name" $wh.name $primaries) -}}
  {{- end -}}
  {{- if and $wh.channels $wh.allowTagsRegex -}}
    {{- fail (printf "warehouse %q sets both `channels` and `allowTagsRegex`; the channel's `image` pattern replaces it, so remove `allowTagsRegex`" $wh.name) -}}
  {{- end -}}
{{- end -}}

{{- /* A stage naming a warehouse that doesn't exist would render a Stage
       requesting freight from nothing, which just never promotes. */ -}}
{{- $whNames := list -}}
{{- range .Values.warehouses -}}{{- $whNames = append $whNames .name -}}{{- end -}}
{{- range .Values.stages -}}
  {{- $stage := . -}}
  {{- range $stage.warehouses -}}
    {{- if not (has . $whNames) -}}
      {{- fail (printf "stage %q references warehouse %q, which is not defined in warehouses[]" $stage.name .) -}}
    {{- end -}}
  {{- end -}}
  {{- if $stage.upstream -}}
    {{- $upstreamNames := list -}}
    {{- range $.Values.stages -}}{{- $upstreamNames = append $upstreamNames .name -}}{{- end -}}
    {{- if not (has $stage.upstream $upstreamNames) -}}
      {{- fail (printf "stage %q sets upstream %q, which is not a stage in this project" $stage.name $stage.upstream) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
