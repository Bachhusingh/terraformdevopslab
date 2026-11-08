hcl
resource "aws_ecr_repository" "app" {
  name                 = "${var.env}-releaseops-app"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }   # ≈ ACR Microsoft Defender image scan
}

resource "aws_ecr_lifecycle_policy" "expire_untagged" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after 7 days"
      selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 7 }
      action       = { type = "expire" }
    }]
  })
}