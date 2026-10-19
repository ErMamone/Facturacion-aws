output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "alb_security_group_id" {
  description = "SG para la anotación alb.ingress.kubernetes.io/security-groups del Ingress."
  value       = aws_security_group.alb.id
}

output "facturas_bucket" {
  value = aws_s3_bucket.facturas.bucket
}

output "facturas_prefix" {
  value = var.facturas_prefix
}

output "rds_endpoint" {
  description = "host:puerto de PostgreSQL."
  value       = aws_db_instance.this.endpoint
}

output "rds_db_name" {
  value = aws_db_instance.this.db_name
}

output "rds_master_secret_arn" {
  description = "Secret de Secrets Manager con usuario y password de RDS."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "backend_irsa_role_arn" {
  description = "Para la anotación eks.amazonaws.com/role-arn del ServiceAccount del backend."
  value       = module.backend_irsa.arn
}
