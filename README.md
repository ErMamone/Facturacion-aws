# Facturacion-aws

Infraestructura de la app de facturación sobre AWS (EKS Fargate + RDS + S3), con OpenTofu.
Cada sesión de demo levanta el entorno, lo usa y lo destruye.

## Estructura

```
infra/
  bootstrap/   permanente: bucket de state, OIDC de GitHub, rol de CI, ECR, budget y anomalías
  env/         efímero (up/down por sesión): VPC, EKS Fargate, IRSA, LB Controller, RDS, S3
scripts/
  check-orphans.sh   después del destroy, busca recursos que siguen cobrando
docs/
  INSTALACION.md     herramientas, validación local y primer apply de bootstrap
.github/workflows/
  infra-ci.yml       fmt, validate, tflint, shellcheck y trivy en dev/prd
```

## Ramas

`dev` → PR → `prd`. `infra-ci` corre en los push y PR de ambas ramas.

## Decisiones

| Tema | Decisión | Motivo / trade-off |
|---|---|---|
| Herramienta | OpenTofu 1.13.x | Lock nativo en S3 (`use_lockfile`), sin DynamoDB |
| Región | `us-east-1` | Costos calculados ahí (doc 02) |
| State | `facturacion-tfstate-<account_id>`, versionado, privado, SSE-S3, solo TLS | **Sin** cifrado de state de OpenTofu: quien accede al bucket ya tiene acceso a la cuenta. Además, el password de RDS no pasa por el state |
| Password de RDS | `manage_master_user_password = true` | Lo genera RDS en Secrets Manager |
| Auth CI → AWS | OIDC, rol `gha-facturacion` | Trust policy limitada a `repo:ErMamone/Facturacion-aws:environment:demo` |
| Permisos del rol de CI | Comodines por servicio, solo en `us-east-1`; IAM solo sobre `facturacion-*` | Arrancar amplio y achicar con IAM Access Analyzer |
| Endpoint de la API de EKS | Público, auth IAM + access entries | Restringirlo por CIDR exige mantener los rangos de GitHub Actions |
| ALB | `allowed_cidrs` default `0.0.0.0/0` | La app es pública mientras dura la sesión. Para cerrarla: `allowed_cidrs = ["<ip>/32"]` |
| Budget | 10 USD/mes, alertas a 50 % y 100 % reales y 100 % forecast; **sin créditos** | Con créditos incluidos el costo neto es 0 y nunca alertaría |
| Anomalías | Monitor por servicio, email diario si el impacto es ≥ 5 USD | |
| EKS | 1.37, `upgrade_policy = STANDARD`, sin logs del control plane ni KMS | Evita Extended Support y log groups huérfanos |

## Uso

Ver [docs/INSTALACION.md](docs/INSTALACION.md).

Outputs de `env` que necesitan los manifiestos de la app:

- `backend_irsa_role_arn` → anotación `eks.amazonaws.com/role-arn` del ServiceAccount `facturacion-back` (namespace `facturacion`)
- `alb_security_group_id` → anotaciones del Ingress:
  ```yaml
  alb.ingress.kubernetes.io/security-groups: <alb_security_group_id>
  alb.ingress.kubernetes.io/manage-backend-security-group-rules: "true"
  alb.ingress.kubernetes.io/target-type: ip
  ```
- `rds_endpoint`, `rds_db_name`, `rds_master_secret_arn`, `facturas_bucket`, `facturas_prefix`

## Pendiente

- Workflows `up`, `down` y `auto-destroy` (doc 07).
- Trivy en modo bloqueante, después de documentar los hallazgos aceptados en `.trivyignore`.
- Achicar los permisos del rol de CI con IAM Access Analyzer.
