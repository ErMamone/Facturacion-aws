# Repositorios de imágenes. Viven en bootstrap para sobrevivir al destroy de env.

locals {
  ecr_repos = toset(["back", "web"])
}

resource "aws_ecr_repository" "this" {
  for_each = local.ecr_repos

  name = "${var.project}-${each.key}"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# ECR cobra por GB almacenado: se conservan solo las últimas N imágenes.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Conservar las ultimas ${var.ecr_keep_images} imagenes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.ecr_keep_images
      }
      action = {
        type = "expire"
      }
    }]
  })
}
