# Backend parcial: el bucket se pasa en `tofu init` porque su nombre lleva el
# account ID y el backend no admite valores dinámicos:
#
#   tofu init -backend-config="bucket=facturacion-tfstate-<account_id>"
#
# Primer apply (el bucket todavía no existe): ver docs/INSTALACION.md,
# sección "Bootstrap". Se usa un backend_override.tf local y después
# `tofu init -migrate-state`.
terraform {
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
