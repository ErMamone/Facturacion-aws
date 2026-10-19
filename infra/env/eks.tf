# Cluster EKS solo Fargate.
#
# Endpoint de la API: público (0.0.0.0/0) y protegido por IAM + access entries.
# Trade-off aceptado: restringirlo por CIDR implica mantener los rangos de
# GitHub Actions, que son muchos y cambian. El cluster vive minutos/horas.

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

  # STANDARD: nunca entra en Extended Support (+0,50 USD/h); al vencer el
  # soporte estándar, AWS actualiza la versión.
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

  # Sin logs del control plane ni log group (doc 02: log groups sin retención).
  enabled_log_types           = []
  create_cloudwatch_log_group = false

  # Sin KMS propio para secrets (0 costo; cluster efímero).
  create_kms_key    = false
  encryption_config = null

  # Sin nodos EC2.
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
    # Fargate-only: CoreDNS tiene que poder agendarse en Fargate.
    coredns = {
      configuration_values = jsonencode({
        computeType = "Fargate"
      })
    }
    kube-proxy = {}
    vpc-cni    = {}
  }
}
