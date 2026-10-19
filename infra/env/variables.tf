variable "region" {
  description = "Región de AWS."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nombre del proyecto. Se usa en tags, como nombre del cluster y como prefijo de recursos."
  type        = string
  default     = "facturacion"
}

variable "expires_at" {
  description = "Fecha/hora UTC (RFC 3339, ej. 2026-10-19T23:00:00Z) en que auto-destroy baja el entorno. Se guarda como tag de la VPC. Vacío = se destruye en la próxima corrida de auto-destroy."
  type        = string
  default     = ""

  validation {
    condition     = var.expires_at == "" || can(formatdate("YYYY", var.expires_at))
    error_message = "expires_at tiene que ser RFC 3339, ej. 2026-10-19T23:00:00Z."
  }
}

# --- Red -----------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR de la VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "excluded_az_ids" {
  description = "AZ IDs donde no se crean subnets. use1-az3 no soporta EKS ni Fargate."
  type        = list(string)
  default     = ["use1-az3"]
}

variable "allowed_cidrs" {
  description = "CIDRs que pueden entrar al ALB por HTTP. Default: público. Para restringir, pasar [\"<tu-ip>/32\"]."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- EKS -----------------------------------------------------------------------

variable "kubernetes_version" {
  description = "Versión de Kubernetes. Tiene que estar en soporte estándar (Extended Support suma 0,50 USD/h)."
  type        = string
  default     = "1.37"
}

variable "ci_role_name" {
  description = "Nombre del rol de CI creado en bootstrap. Recibe un access entry de admin del cluster."
  type        = string
  default     = "gha-facturacion"
}

variable "admin_principal_arns" {
  description = "ARNs IAM extra (ej. tu usuario) con admin del cluster. Necesario si aplicás env desde tu máquina."
  type        = list(string)
  default     = []
}

variable "app_namespace" {
  description = "Namespace de la app. Tiene su propio Fargate profile."
  type        = string
  default     = "facturacion"
}

variable "backend_service_account" {
  description = "ServiceAccount del backend que asume el rol IRSA."
  type        = string
  default     = "facturacion-back"
}

variable "lb_controller_chart_version" {
  description = "Versión del chart aws-load-balancer-controller (https://aws.github.io/eks-charts)."
  type        = string
  default     = "3.6.0"
}

# --- Datos ---------------------------------------------------------------------

variable "facturas_prefix" {
  description = "Prefijo dentro del bucket al que el backend tiene acceso."
  type        = string
  default     = "facturas/"
}

variable "facturas_retention_days" {
  description = "Días que viven los objetos del bucket de facturas."
  type        = number
  default     = 31
}

variable "db_engine_version" {
  description = "Versión mayor de PostgreSQL. RDS elige la minor por defecto."
  type        = string
  default     = "18"
}

variable "db_instance_class" {
  description = "Clase de instancia de RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Storage de RDS en GB (gp3)."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Nombre de la base de datos inicial."
  type        = string
  default     = "facturacion"
}

variable "db_username" {
  description = "Usuario master de RDS. El password lo genera RDS en Secrets Manager."
  type        = string
  default     = "facturacion"
}
