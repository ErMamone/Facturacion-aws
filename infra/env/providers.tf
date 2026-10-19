provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project = var.project
    }
  }
}

# Helm se autentica contra el cluster con el mismo principal que corre tofu
# (CI o tu usuario), vía `aws eks get-token`. Ese principal necesita un
# access entry: ver access_entries en eks.tf.
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  name       = var.project
  account_id = data.aws_caller_identity.current.account_id
}
