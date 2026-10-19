# Facturacion-aws

Infraestructura de la app de facturación sobre AWS (EKS Fargate + RDS + S3), con OpenTofu.
Cada sesión de demo levanta el entorno, lo usa y lo destruye.

## Estructura

```
infra/
  bootstrap/   permanente: bucket de state, OIDC de GitHub, rol de CI, ECR, budget y anomalías
  env/         efímero (up/down por sesión): VPC, EKS Fargate, IRSA, LB Controller, RDS, S3
k8s/base/            manifiestos de la app (back, web, Ingress); el overlay se genera en cada up
scripts/
  render-k8s.sh      genera el overlay de Kustomize con los outputs de tofu
  teardown.sh        down en orden: Ingress -> espera ALB -> destroy -> check-orphans
  check-orphans.sh   después del destroy, busca recursos que siguen cobrando
docs/
  INSTALACION.md     herramientas, validación local y primer apply de bootstrap
  OPERACION.md       configuración de GitHub, up / down / auto-destroy, troubleshooting
.github/workflows/
  infra-ci.yml       fmt, validate, tflint, shellcheck, kustomize y trivy en dev/prd
  up.yml             levanta infra + despliega la app (environment demo, con aprobación)
  down.yml           baja todo (environment teardown)
  auto-destroy.yml   cada hora: baja el entorno si venció su TTL
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
| Auth CI → AWS | OIDC, un solo rol `gha-facturacion` para los 3 repos | Trust policy limitada a environments: `demo` en los 3 repos (con aprobación) y `teardown` en Facturacion-aws (sin aprobación, solo rama `prd`) |
| Auto-destroy | Cada hora, TTL por entorno (tag `expires-at` en la VPC, default 3 h) | Un olvido cuesta como mucho unas horas. Un `up` fallido también se limpia |
| Manifiestos | `k8s/` en este repo, Kustomize | Están al lado de los outputs de tofu que necesitan |
| Permisos del rol de CI | Comodines por servicio, solo en `us-east-1`; IAM solo sobre `facturacion-*` | Arrancar amplio y achicar con IAM Access Analyzer |
| Endpoint de la API de EKS | Público, auth IAM + access entries | Restringirlo por CIDR exige mantener los rangos de GitHub Actions |
| ALB | `allowed_cidrs` default `0.0.0.0/0` | La app es pública mientras dura la sesión. Para cerrarla: `allowed_cidrs = ["<ip>/32"]` |
| Budget | 10 USD/mes, alertas a 50 % y 100 % reales y 100 % forecast; **sin créditos** | Con créditos incluidos el costo neto es 0 y nunca alertaría |
| Anomalías | Monitor por servicio, email diario si el impacto es ≥ 5 USD | |
| EKS | 1.37, `upgrade_policy = STANDARD`, sin logs del control plane ni KMS | Evita Extended Support y log groups huérfanos |

## Uso

1. [docs/INSTALACION.md](docs/INSTALACION.md): herramientas y bootstrap (una vez).
2. [docs/OPERACION.md](docs/OPERACION.md): configuración de GitHub y operación de cada sesión.

## Pendiente

- Primera sesión real: medir tiempos de `up`/`down` y costo contra el doc 02.
- Trivy en modo bloqueante, después de documentar los hallazgos aceptados en `.trivyignore`.
- Achicar los permisos del rol de CI con IAM Access Analyzer.
