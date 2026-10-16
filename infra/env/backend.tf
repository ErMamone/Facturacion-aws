# Backend parcial: el bucket se pasa en `tofu init`:
#
#   tofu init -backend-config="bucket=facturacion-tfstate-<account_id>"
terraform {
  backend "s3" {
    key          = "env/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
