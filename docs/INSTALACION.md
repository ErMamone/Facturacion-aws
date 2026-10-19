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

## 3. Credenciales de AWS

Sin access keys: se usa `aws login` (AWS CLI 2.32 o posterior), que toma la sesión de la consola y genera credenciales temporales de hasta 12 h. No queda nada de larga duración en tu máquina que se pueda filtrar (doc 03, amenaza 1).

### 3.1 En la consola (una sola vez)

1. **Root con MFA.** Entrá como root → menú de la cuenta (arriba a la derecha) → **Security credentials** → **Assign MFA device**. Después de este paso no se vuelve a usar el root.
2. **Usuario admin.** **IAM → Users → Create user**:
   - Nombre: el que quieras (ej. `eros-admin`).
   - Tildar **Provide user access to the AWS Management Console** → *I want to create an IAM user* → password propia.
   - **Permissions → Attach policies directly → `AdministratorAccess`**. Ya incluye los permisos de `aws login`; si algún día usás una policy más chica, sumá `SignInLocalDevelopmentAccess`.
3. **MFA del usuario.** Cerrá sesión del root y entrá con el usuario nuevo. La URL de login está en **IAM → Dashboard → AWS sign-in URL**, con la forma `https://<account_id>.signin.aws.amazon.com/console`. Después: **IAM → Users → (tu usuario) → Security credentials → Assign MFA device**.
4. **No crees access keys.**

### 3.2 En tu máquina

```powershell
aws --version   # tiene que ser 2.32 o posterior

# Abre el navegador: elegí la sesión de tu usuario admin (no la de root)
aws login --profile facturacion-login
# Region: us-east-1
```

Algunas herramientas (como el provider de AWS de OpenTofu) todavía no entienden los perfiles de `aws login`. Para esos casos se arma un segundo perfil que le pide las credenciales a la CLI. Agregalo al final de `%USERPROFILE%\.aws\config`:

```ini
[profile facturacion-admin]
credential_process = aws configure export-credentials --profile facturacion-login --format process
region = us-east-1
```

Probalo:

```powershell
$env:AWS_PROFILE = "facturacion-admin"
aws sts get-caller-identity
# "Arn": "arn:aws:iam::<account_id>:user/<tu-usuario>"   <- tu usuario, no root
```

Cada sesión dura como mucho 12 h. Cuando expire (`ExpiredToken` o un error de credenciales), volvé a correr `aws login --profile facturacion-login`. Al terminar podés cerrarla con `aws logout --profile facturacion-login`.

En una terminal nueva hay que volver a setear `$env:AWS_PROFILE = "facturacion-admin"`.

## 4. Bootstrap (una sola vez)

El bucket de state lo crea el propio `bootstrap`, así que el primer apply se hace con state local y después se migra.

```powershell
cd infra/bootstrap
Copy-Item terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars: alert_email
```

**4.1 Primer apply con backend local.** Un archivo `*_override.tf` (ignorado por git) reemplaza el backend S3:

```powershell
# WriteAllText escribe UTF-8 sin BOM (Set-Content -Encoding utf8 en PowerShell 5.1 agrega BOM)
[IO.File]::WriteAllText("$PWD\backend_override.tf", "terraform {`n  backend `"local`" {}`n}`n")

tofu init
tofu plan -out bootstrap.tfplan
tofu apply bootstrap.tfplan
```

Si falla `aws_ce_anomaly_monitor` con `User not enabled for cost explorer access`: como root, **Account → IAM user and role access to Billing information → Activate IAM Access**, y abrí **Cost Explorer** una vez para activarlo. Tarda hasta 24 h; mientras tanto poné `enable_anomaly_detection = false` en `terraform.tfvars`, seguí con los pasos siguientes y volvé a ponerlo en `true` cuando esté listo.

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

## 5. GitHub y operación diaria

La configuración de GitHub (environments, variables) y cómo levantar y bajar el entorno están en [OPERACION.md](OPERACION.md).

## 6. Stack env desde tu máquina (opcional)

Lo normal es usar los workflows `up` y `down`. Para probar a mano:

```powershell
cd infra/env
$account = aws sts get-caller-identity --query Account --output text
tofu init -backend-config="bucket=facturacion-tfstate-$account"

# - admin_principal_arns: tu usuario necesita admin del cluster para que Helm
#   instale el LB Controller.
# - expires_at: sin este tag, auto-destroy baja el entorno en su próxima corrida.
# Van por terraform.tfvars (ignorado por git) porque PowerShell 5.1 rompe las
# comillas dentro de -var.
$me = aws sts get-caller-identity --query Arn --output text
$exp = (Get-Date).ToUniversalTime().AddHours(3).ToString("yyyy-MM-ddTHH:mm:ssZ")
[IO.File]::WriteAllText("$PWD\terraform.tfvars", "admin_principal_arns = [`"$me`"]`nexpires_at = `"$exp`"`n")

tofu plan -out env.tfplan
tofu apply env.tfplan
```

Para bajarlo, desde Git Bash en la raíz del repo (usa `aws`, `kubectl` y `tofu`):

```bash
AWS_PROFILE=facturacion-admin scripts/teardown.sh
```
