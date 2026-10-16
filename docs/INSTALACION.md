# Instalación y validación local

Guía para Windows 11 (PowerShell). Primero se instalan las herramientas, después se valida el código sin tocar AWS y por último se aplica `bootstrap`.

## 1. Herramientas

| Herramienta | Versión | Para qué |
|---|---|---|
| OpenTofu | 1.13.x | `tofu fmt/validate/plan/apply` |
| AWS CLI | v2 | credenciales, `aws eks get-token` (lo usa Helm), `check-orphans.sh` |
| TFLint | 0.64.0 | lint de HCL + reglas de AWS |
| Trivy | 0.75.x | escaneo de misconfiguraciones (`trivy config`) |
| ShellCheck | 0.11.x | lint de `scripts/*.sh` |
| kubectl | 1.37 | operar el cluster (`delete ingress` en el down) |
| Helm | 3.x/4.x | opcional, para inspeccionar releases |

```powershell
winget install --exact --id OpenTofu.Tofu --version 1.13.1
winget install --exact --id Amazon.AWSCLI
winget install --exact --id TerraformLinters.tflint --version 0.64.0
winget install --exact --id AquaSecurity.Trivy --version 0.75.0
winget install --exact --id koalaman.shellcheck
winget install --exact --id Kubernetes.kubectl
winget install --exact --id Helm.Helm
```

Cerrá y volvé a abrir la terminal para que tome el `PATH`, y verificá:

```powershell
tofu version
aws --version
tflint --version
trivy --version
shellcheck --version
kubectl version --client
```

> Si `winget` no encuentra la versión exacta, sacá `--version` e instalá la última; para OpenTofu respetá la 1.13.x porque está fijada en `required_version`.

## 2. Validación local (no necesita AWS)

Desde la raíz del repo. Es lo mismo que corre `.github/workflows/infra-ci.yml`.

```powershell
# Formato
tofu fmt -check -recursive -diff infra

# Validate de cada stack (sin backend: no se conecta a S3)
tofu -chdir=infra/bootstrap init -backend=false
tofu -chdir=infra/bootstrap validate
tofu -chdir=infra/env init -backend=false
tofu -chdir=infra/env validate

# TFLint (baja el plugin de AWS la primera vez)
tflint --init --config="$PWD/.tflint.hcl"
tflint --chdir=infra/bootstrap --config="$PWD/.tflint.hcl"
tflint --chdir=infra/env --config="$PWD/.tflint.hcl"

# Trivy
trivy config --severity HIGH,CRITICAL infra

# ShellCheck
shellcheck scripts/check-orphans.sh
```

Si `tofu fmt -check` falla, corré `tofu fmt -recursive infra` y commiteá el resultado.

### Lock files de providers

`tofu init` genera `.terraform.lock.hcl` en cada stack. **Se commitean.** Como vos estás en Windows y el CI corre en Linux, agregá los hashes de ambas plataformas:

```powershell
tofu -chdir=infra/bootstrap providers lock -platform=windows_amd64 -platform=linux_amd64
tofu -chdir=infra/env providers lock -platform=windows_amd64 -platform=linux_amd64
```

## 3. Credenciales de AWS (solo para bootstrap)

Según el doc 03: usuario IAM admin propio con MFA; las access keys locales se usan **solo** para aplicar `bootstrap` y después se borran o se rotan fuera del repo.

```powershell
aws configure --profile facturacion-admin
# region: us-east-1, output: json

$env:AWS_PROFILE = "facturacion-admin"
aws sts get-caller-identity
```

## 4. Bootstrap (una sola vez)

El bucket de state lo crea el propio `bootstrap`, así que el primer apply se hace con state local y después se migra.

```powershell
cd infra/bootstrap
Copy-Item terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars: alert_email
```

**4.1 Primer apply con backend local.** Un archivo `*_override.tf` (ignorado por git) reemplaza el backend S3:

```powershell
@'
terraform {
  backend "local" {}
}
'@ | Set-Content -Encoding utf8 backend_override.tf

tofu init
tofu plan -out bootstrap.tfplan
tofu apply bootstrap.tfplan
```

Si falla `aws_ce_anomaly_monitor` porque la cuenta ya tiene un monitor por servicio, buscalo con `aws ce get-anomaly-monitors`, poné `create_anomaly_monitor = false` y `existing_anomaly_monitor_arn = "..."` en `terraform.tfvars`, y volvé a aplicar.

**4.2 Migrar el state a S3.**

```powershell
Remove-Item backend_override.tf
$account = aws sts get-caller-identity --query Account --output text
tofu init -migrate-state -backend-config="bucket=facturacion-tfstate-$account"
# Responder "yes" a copiar el state existente
tofu plan   # tiene que dar "No changes"
Remove-Item terraform.tfstate*, bootstrap.tfplan
```

**4.3 Confirmar las suscripciones de email.** AWS manda un mail de confirmación para las alertas de anomalías; aceptalo.

**4.4 Anotar los outputs:**

```powershell
tofu output
```

`gha_role_arn` es el rol que van a asumir los workflows.

## 5. Configuración de GitHub (manual)

Desde Settings del repo:

- [ ] **Environments → New environment `demo`** → Required reviewers: vos. Ningún job puede asumir el rol de AWS sin pasar por este environment (la trust policy exige `environment:demo`).
- [ ] **Code security → Secret scanning** y **Push protection**: activados.
- [ ] **Branches**: crear `dev`; proteger `prd` (merge solo por PR desde `dev` con `infra-ci` en verde).

No se carga ningún secret de AWS en GitHub.

## 6. Stack env desde tu máquina (opcional, para la primera prueba)

Lo normal es levantarlo con el workflow `up` (doc 07). Para probar a mano:

```powershell
cd infra/env
$account = aws sts get-caller-identity --query Account --output text
tofu init -backend-config="bucket=facturacion-tfstate-$account"

# Tu usuario necesita admin del cluster para que Helm instale el LB Controller.
# Se pasa por terraform.tfvars (ignorado por git): PowerShell 5.1 rompe las
# comillas dentro de -var.
$me = aws sts get-caller-identity --query Arn --output text
"admin_principal_arns = [`"$me`"]" | Set-Content -Encoding utf8 terraform.tfvars

tofu plan -out env.tfplan
tofu apply env.tfplan
```

### Down (el orden importa, doc 04)

```powershell
aws eks update-kubeconfig --name facturacion --region us-east-1
kubectl delete ingress --all -n facturacion
# Esperar hasta que no quede ALB del cluster:
aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerName"
tofu destroy
bash ../../scripts/check-orphans.sh facturacion us-east-1
```
