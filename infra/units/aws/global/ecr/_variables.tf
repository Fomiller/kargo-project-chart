variable "chart_prefix" {
  description = "ECR path prefix all charts are published under. Must match the registry path the release workflow pushes to."
  type        = string
  default     = "charts"
}

variable "chart_name" {
  description = "Chart name, which is also the last path segment helm push writes to."
  type        = string
  default     = "kargo-project"
}
