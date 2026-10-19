# IRSA: roles IAM asumidos por ServiceAccounts de Kubernetes vía el OIDC del cluster.
# Los nombres de roles y policies empiezan con "<project>-" porque el rol de CI
# solo puede escribir IAM con ese prefijo (ver bootstrap/github_oidc.tf).

module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name        = "${local.name}-lb-controller"
  policy_name = "${local.name}-lb-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# Backend: acceso a su prefijo del bucket de facturas y lectura del password de RDS.
data "aws_iam_policy_document" "backend" {
  statement {
    sid       = "ObjetosFacturas"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.facturas.arn}/${var.facturas_prefix}*"]
  }

  statement {
    sid       = "ListarPrefijoFacturas"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.facturas.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.facturas_prefix}*"]
    }
  }

  statement {
    sid       = "PasswordRds"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_db_instance.this.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_policy" "backend" {
  name_prefix = "${local.name}-backend-"
  description = "Backend de facturacion: S3 acotado a su prefijo y password de RDS"
  policy      = data.aws_iam_policy_document.backend.json
}

module "backend_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name          = "${local.name}-backend"
  create_policy = false

  policies = {
    backend = aws_iam_policy.backend.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.app_namespace}:${var.backend_service_account}"]
    }
  }
}
