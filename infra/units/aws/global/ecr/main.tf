# ECR repository holding this repo's Helm chart as an OCI artifact.
#
# The name is the chart's name, with nothing in front of it. `helm push`
# appends the chart's own name to the registry path it is given, so CI pushes
# to the bare registry and the chart lands here.
#
# It used to sit under a charts/ prefix. Nothing needed the grouping — images
# live at the registry root too — and it cost consumers a real bug: kustomize
# builds a local directory out of helmCharts[].name, so a slash in the name
# resolves to a path that does not exist.

resource "aws_ecr_repository" "chart" {
  name = var.chart_name

  # Chart versions are semver and never republished, so a re-push of an existing
  # version is a bug in the release workflow. Fail it at the registry.
  image_tag_mutability = "IMMUTABLE"

  # The repository name is part of this resource's identity, so renaming it
  # replaces it, and a replace has to delete a repository that holds published
  # charts. Allowed because a chart artifact is not the source of truth: the
  # git tag is, and the release workflow can push it again.
  force_delete = true

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
