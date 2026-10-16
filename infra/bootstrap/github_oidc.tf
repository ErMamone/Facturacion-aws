# GitHub Actions -> AWS por OIDC. Cero access keys en GitHub.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# Solo los jobs que corren en el environment `demo` de este repo pueden asumir
# el rol. Ni forks, ni otras ramas, ni jobs sin environment.
data "aws_iam_policy_document" "gha_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:environment:${var.github_environment}"]
    }
  }
}

resource "aws_iam_role" "gha" {
  name                 = "gha-${var.project}"
  description          = "Rol asumido por GitHub Actions (${var.github_repo}, environment ${var.github_environment})"
  assume_role_policy   = data.aws_iam_policy_document.gha_trust.json
  max_session_duration = 3600
}

# Permisos "amplios pero acotados" para arrancar (doc 03). Después de las
# primeras sesiones, achicar con IAM Access Analyzer (generar policy a partir
# de CloudTrail) y reemplazar los comodines por servicio.
data "aws_iam_policy_document" "gha" {
  # Servicios que usa el stack env y los workflows, solo en la región del proyecto.
  # La condición de región evita que, si el rol se compromete, se levanten
  # recursos (ej. minería) en otras regiones.
  statement {
    sid = "ServiciosDelProyecto"
    actions = [
      "ec2:*",
      "eks:*",
      "elasticloadbalancing:*",
      "rds:*",
      "s3:*",
      "ecr:*",
      "secretsmanager:*",
      "logs:*",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # RDS cifra el storage con aws/rds y guarda el password en Secrets Manager
  # (aws/secretsmanager): necesita usar esas claves administradas por AWS.
  statement {
    sid = "KmsClavesAdministradas"
    actions = [
      "kms:CreateGrant",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ListAliases",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "IamLectura"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # Escritura en IAM solo sobre roles y policies con el prefijo del proyecto.
  # Todos los roles/policies del stack env se nombran "<project>-...".
  statement {
    sid = "IamRolesDelProyecto"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:CreateRole",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PassRole",
      "iam:PutRolePolicy",
      "iam:TagPolicy",
      "iam:TagRole",
      "iam:UntagPolicy",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project}-*",
      "arn:${local.partition}:iam::${local.account_id}:policy/${var.project}-*",
    ]
  }

  # OIDC provider del cluster EKS (IRSA).
  statement {
    sid = "IamOidcEks"
    actions = [
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:oidc-provider/oidc.eks.${var.region}.amazonaws.com/*"]
  }

  statement {
    sid       = "IamServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "eks.amazonaws.com",
        "eks-fargate.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
        "rds.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role_policy" "gha" {
  name   = "gha-${var.project}"
  role   = aws_iam_role.gha.id
  policy = data.aws_iam_policy_document.gha.json
}
