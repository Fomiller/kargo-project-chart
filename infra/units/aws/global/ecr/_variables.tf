variable "chart_name" {
  description = "Chart name. Also the repository name, and the last path segment helm push writes to."
  type        = string
  default     = "kargo-project-chart"
}
