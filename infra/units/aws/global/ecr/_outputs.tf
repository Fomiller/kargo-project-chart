output "ecr_repository_url" {
  description = "Full repository URL, e.g. <account>.dkr.ecr.<region>.amazonaws.com/charts/kargo-project-chart"
  value       = aws_ecr_repository.chart.repository_url
}

output "ecr_registry" {
  description = "Registry host alone. The release workflow pushes to oci://<registry>/<chart_prefix>."
  value       = split("/", aws_ecr_repository.chart.repository_url)[0]
}
