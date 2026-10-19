data "aws_iam_role" "ci" {
  name = var.ci_role_name
}

locals {
  cluster_admin_policy = {
    admin = {
      policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      access_scope = {
        type = "cluster"
      }
    }
  }

  access_entries = merge(
    {
      ci = {
        principal_arn       = data.aws_iam_role.ci.arn
        policy_associations = local.cluster_admin_policy
      }
    },
    {
      for i, arn in var.admin_principal_arns : "admin-${i}" => {
        principal_arn       = arn
        policy_associations = local.cluster_admin_policy
      }
    },
  )
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29"

  name               = local.name
  kubernetes_version = var.kubernetes_version

  upgrade_policy = {
    support_type = "STANDARD"
  }

  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.private[*].id

  endpoint_public_access  = true
  endpoint_private_access = true

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries                           = local.access_entries

  enabled_log_types           = []
  create_cloudwatch_log_group = false

  create_kms_key    = false
  encryption_config = null

  create_node_security_group = false

  fargate_profiles = {
    kube-system = {
      selectors     = [{ namespace = "kube-system" }]
      iam_role_name = "${local.name}-fargate-kube-system"
    }
    app = {
      name          = var.app_namespace
      selectors     = [{ namespace = var.app_namespace }]
      iam_role_name = "${local.name}-fargate-app"
    }
  }

  addons = {
    coredns = {
      configuration_values = jsonencode({
        computeType = "Fargate"
      })
    }
    kube-proxy = {}
    vpc-cni    = {}
  }
}
