# ECR repository holding this repo's Helm chart as an OCI artifact.
#
# The name has to be "<prefix>/<chart name>", because `helm push` appends the
# chart's own name to the registry path it is given. CI pushes to
# oci://<account>.dkr.ecr.<region>.amazonaws.com/charts, so a chart named
# kargo-project-chart lands in charts/kargo-project-chart. Adding a second chart to this
# repo means adding a second repository here.

resource "aws_ecr_repository" "chart" {
  name = "${var.chart_prefix}/${var.chart_name}"

  # Chart versions are semver and never republished, so a re-push of an existing
  # version is a bug in the release workflow. Fail it at the registry.
  image_tag_mutability = "IMMUTABLE"

  # Image scanning targets container layers; a chart artifact has none.
  image_scanning_configuration {
    scan_on_push = false
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Owner       = "Forrest Miller"
    Environment = var.environment
  }
}

# A failed or interrupted push can leave an untagged manifest behind. Nothing
# ever references one, so there is no reason to keep them.
resource "aws_ecr_lifecycle_policy" "chart" {
  repository = aws_ecr_repository.chart.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged manifests after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}
