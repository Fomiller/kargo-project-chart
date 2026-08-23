variable "chart_name" {
  description = "Chart name. Also the repository name, and the last path segment helm push writes to."
  type        = string
  default     = "kargo-project-chart"
}

# Temporary. The repository is still at the old prefixed name because the
# rename has to happen in two applies: force_delete is read from state when
# terraform destroys the old repository, so it has to be committed to state
# before the name changes. Removed in the follow-up that drops the prefix.
variable "chart_prefix" {
  description = "Legacy path prefix the repository still sits under."
  type        = string
  default     = "charts"
}
