# RDS PostgreSQL + bucket S3 de facturas. Todo descartable: se destruye por sesión.

# --- RDS -----------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = local.name
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds"
  description = "RDS: PostgreSQL solo desde los pods"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name}-rds"
  }
}

# Los pods de Fargate usan el security group primario del cluster.
resource "aws_vpc_security_group_ingress_rule" "rds_from_pods" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL desde los pods (SG primario del cluster)"
  referenced_security_group_id = module.eks.cluster_primary_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_db_instance" "this" {
  identifier     = local.name
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  # RDS genera el password y lo guarda en Secrets Manager. No pasa por el state.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  # Datos descartables: sin backups automáticos ni snapshot final.
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  auto_minor_version_upgrade = true
  apply_immediately          = true
}

# --- S3 facturas ----------------------------------------------------------------

resource "aws_s3_bucket" "facturas" {
  bucket = "${local.name}-data-${local.account_id}"

  # Se puede destruir con objetos adentro.
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "facturas" {
  bucket = aws_s3_bucket.facturas.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "facturas" {
  bucket = aws_s3_bucket.facturas.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "facturas" {
  bucket = aws_s3_bucket.facturas.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "facturas" {
  bucket = aws_s3_bucket.facturas.id

  rule {
    id     = "expirar-facturas"
    status = "Enabled"

    filter {}

    expiration {
      days = var.facturas_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "facturas" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.facturas.arn,
      "${aws_s3_bucket.facturas.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "facturas" {
  bucket = aws_s3_bucket.facturas.id
  policy = data.aws_iam_policy_document.facturas.json

  depends_on = [aws_s3_bucket_public_access_block.facturas]
}
