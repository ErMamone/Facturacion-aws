variable "region" {
  description = "Región de AWS. Cost Explorer (anomalías) solo existe en us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nombre del proyecto. Se usa en tags y como prefijo de nombres."
  type        = string
  default     = "facturacion"
}

variable "state_bucket_prefix" {
  description = "Prefijo del bucket de state. El nombre final es <prefijo>-<account_id>."
  type        = string
  default     = "facturacion-tfstate"
}

variable "state_noncurrent_days" {
  description = "Días que se conservan las versiones viejas del state antes de borrarlas."
  type        = number
  default     = 90
}

variable "github_oidc_subjects" {
  description = "Claims `sub` de GitHub autorizados a asumir el rol de CI (repo + environment)."
  type        = list(string)
  # Formato de GitHub con IDs inmutables: repo:<owner>@<owner_id>/<repo>@<repo_id>:environment:<env>
  default = [
    "repo:ErMamone@46795580/Facturacion-aws@1421248669:environment:demo",
    "repo:ErMamone@46795580/Facturacion-aws@1421248669:environment:teardown",
    "repo:ErMamone@46795580/Facturacion-back@1421251879:environment:demo",
    "repo:ErMamone@46795580/Facturacion-web@1421254748:environment:demo",
  ]
}

variable "ecr_keep_images" {
  description = "Cantidad de imágenes que conserva cada repositorio de ECR."
  type        = number
  default     = 5
}

variable "alert_email" {
  description = "Email que recibe las alertas de Budget y de Cost Anomaly Detection."
  type        = string
}

variable "budget_limit_usd" {
  description = "Límite mensual del budget, en USD."
  type        = number
  default     = 10
}

variable "anomaly_threshold_usd" {
  description = "Impacto mínimo (USD) para que una anomalía de costo dispare un email."
  type        = number
  default     = 5
}

variable "enable_anomaly_detection" {
  description = "Crear la detección de anomalías (monitor + suscripción por email). Poner false mientras Cost Explorer se activa en una cuenta nueva (hasta 24 h)."
  type        = bool
  default     = true
}

variable "create_anomaly_monitor" {
  description = "Crear el monitor de anomalías por servicio. AWS permite uno solo por cuenta: si ya existe, poner false y pasar existing_anomaly_monitor_arn."
  type        = bool
  default     = true
}

variable "existing_anomaly_monitor_arn" {
  description = "ARN de un monitor de anomalías existente (solo si create_anomaly_monitor = false)."
  type        = string
  default     = null
}
