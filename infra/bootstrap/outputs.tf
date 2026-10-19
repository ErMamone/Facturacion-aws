output "account_id" {
  value = local.account_id
}

output "state_bucket" {
  description = "Bucket de state. Pasarlo en tofu init -backend-config=\"bucket=...\"."
  value       = aws_s3_bucket.state.bucket
}

output "gha_role_arn" {
  description = "Rol que asumen los workflows (aws-actions/configure-aws-credentials -> role-to-assume)."
  value       = aws_iam_role.gha.arn
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
