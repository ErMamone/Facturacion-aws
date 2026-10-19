# Operación: correr todo en AWS

Cómo se pasa del código a la app funcionando en AWS, y cómo se apaga.
Asume que ya hiciste [INSTALACION.md](INSTALACION.md) hasta el paso 4 (bootstrap aplicado).

## Visión general

```
Facturacion-back ──push prd──► CI ──(aprobás)──► ECR facturacion-back:<sha> y :latest
Facturacion-web  ──push prd──► CI ──(aprobás)──► ECR facturacion-web:<sha> y :latest

Facturacion-aws
  up            (botón, aprobás) ──► tofu apply infra/env ──► kubectl apply k8s/ ──► URL del ALB
  down          (botón)          ──► borra Ingress ──► espera ALB ──► tofu destroy ──► check-orphans
  auto-destroy  (cada hora)      ──► si venció expires-at ──► mismo teardown que down
  infra-ci      (push/PR)        ──► fmt, validate, tflint, shellcheck, kustomize, trivy
```

Todos los workflows asumen el rol `gha-facturacion` por OIDC. No hay access keys en GitHub.

| Repo | Environment | Aprobación | Para qué |
|---|---|---|---|
| Facturacion-aws | `demo` | Sí | `up` |
| Facturacion-aws | `teardown` | No (solo rama `prd`) | `down`, `auto-destroy` |
| Facturacion-back | `demo` | Sí | push de imagen a ECR |
| Facturacion-web | `demo` | Sí | push de imagen a ECR |

## 1. Configuración de GitHub (una sola vez)

### En los tres repos

- **Settings → Code security**: activar **Secret scanning** y **Push protection**.
- **Settings → Branches**: proteger `prd` (merge solo por PR desde `dev`, con el CI en verde).

### Facturacion-aws

**Settings → Environments:**

1. `demo`
   - Required reviewers: vos.
   - Deployment branches: *Selected branches* → `prd`.
2. `teardown`
   - **Sin** reviewers (si no, el auto-destroy se queda esperando y no te protege).
   - Deployment branches: *Selected branches* → `prd`.

**Settings → Secrets and variables → Actions → Variables** (a nivel repo):

| Variable | Valor |
|---|---|
| `AWS_ROLE_ARN` | output `gha_role_arn` de bootstrap |
| `CLUSTER_ADMIN_ARNS` | opcional: `["arn:aws:iam::<account>:user/<tu-usuario>"]`, para usar `kubectl` desde tu máquina |

### Facturacion-back y Facturacion-web

**Settings → Environments → `demo`**: Required reviewers vos, Deployment branches `prd`.
Dentro del environment, **Environment variables**:

| Variable | back | web |
|---|---|---|
| `AWS_ROLE_ARN` | output `gha_role_arn` | output `gha_role_arn` |
| `AWS_REGION` | `us-east-1` | `us-east-1` |
| `ECR_REPOSITORY` | `facturacion-back` | `facturacion-web` |

## 2. Publicar las imágenes

`up` no construye imágenes: despliega las que ya están en ECR. Por eso, antes del primer `up`:

1. En Facturacion-back: PR `dev` → `prd` y merge.
2. El CI corre los tests y pide aprobación para el job `imagen` (environment `demo`). Aprobás.
3. La imagen queda en ECR como `facturacion-back:<sha>` y `facturacion-back:latest`.
4. Lo mismo en Facturacion-web.

Para comprobarlo:

```bash
aws ecr describe-images --repository-name facturacion-back --query "imageDetails[].imageTags"
```

## 3. Levantar el entorno (`up`)

1. Facturacion-aws → **Actions → up → Run workflow** (rama `prd`).
2. Inputs:

   | Input | Default | Qué es |
   |---|---|---|
   | `ttl_hours` | 3 | Horas hasta que `auto-destroy` baja todo (1-12) |
   | `allowed_cidrs` | `0.0.0.0/0` | Quién entra al ALB. Para cerrarlo: `<tu-ip>/32` |
   | `retention` | `PT10M` | Vida de cada factura (para ver la purga en vivo) |
   | `back_tag` / `web_tag` | `latest` | Tag de cada imagen en ECR |

3. Aprobás el deployment a `demo`.
4. Esperás unos 25 minutos (EKS es lo más lento; anotá el tiempo real, doc 01).
5. En el **Summary** de la corrida aparecen la URL (`http://facturacion-....elb.amazonaws.com`) y la hora del auto-destroy.

Qué hace, en orden:
1. Valida inputs y verifica que las imágenes existan en ECR (falla antes de gastar plata).
2. `tofu apply` de `infra/env` con `allowed_cidrs` y `expires_at = ahora + ttl_hours`.
3. Crea el Secret `facturacion-db` con usuario y password del secret de RDS.
4. Genera el overlay de Kustomize con los outputs de tofu (`scripts/render-k8s.sh`) y aplica `k8s/`.
5. Espera los rollouts, el ALB y que responda `/` y `/api`.

**Para extender el tiempo:** volvé a correr `up` con otro `ttl_hours`. `tofu apply` no cambia nada salvo el tag `expires-at`, y el deploy es idempotente.

**Para desplegar una versión nueva sin bajar nada:** volvé a correr `up` con el nuevo `back_tag` / `web_tag` (por ejemplo el SHA del commit).

## 4. Bajar el entorno (`down`)

**Actions → down → Run workflow** (rama `prd`). No pide aprobación.

Hace (`scripts/teardown.sh`):
1. `kubectl delete ingress --all -n facturacion` y espera a que el LB Controller borre el ALB.
2. Verifica que el ALB `facturacion` ya no existe. Si sigue, **no** corre el destroy y falla.
3. `tofu destroy`.
4. `scripts/check-orphans.sh`: si encuentra NAT, EIP, ALB, ENIs, SG o log groups sueltos, el job falla.

Si te olvidás, `auto-destroy` lo hace solo cuando vence el `ttl_hours`.

## 5. Auto-destroy

Corre cada hora (minuto 17). Busca la VPC con tag `project=facturacion`:
- No existe → no hace nada.
- Tiene `expires-at` y todavía no venció → no hace nada.
- Venció, o no tiene `expires-at` (un `up` que falló, un apply manual sin `expires_at`) → teardown.

Usa el mismo grupo de concurrencia que `up` y `down` (`env-demo`): nunca corren a la vez. Si dispara mientras corre un `up`, espera a que termine y vuelve a leer el tag.

Ojo: GitHub deshabilita los workflows `schedule` de repos públicos después de **60 días sin actividad**. Si pasa, reactivalo desde Actions. El budget sigue siendo la última red.

## 6. Usar kubectl desde tu máquina

Con `CLUSTER_ADMIN_ARNS` configurada (paso 1) y un `up` corrido después de configurarla:

```bash
aws eks update-kubeconfig --name facturacion --region us-east-1
kubectl get pods -n facturacion
kubectl logs -n facturacion deploy/facturacion-back
```

## 7. Si algo sale mal

| Síntoma | Qué hacer |
|---|---|
| `up` falla en "Verificar imágenes" | Falta la imagen en ECR: paso 2 |
| `up` falla en `tofu apply` | Leer el error. Corré `down` para no pagar lo que haya quedado creado. Si no, lo baja `auto-destroy` cuando vence el `ttl_hours` |
| `rollout status` timeout | `kubectl describe pod` / `kubectl logs`. Lo más común: la app no conecta a RDS o falta una variable |
| El ALB no responde | Targets unhealthy: revisar el health check (`/actuator/health/readiness`) y los logs del backend |
| `down` falla en "Esperando que no quede el ALB" | Ver en la consola de EC2 → Load Balancers si quedó `facturacion` y borrarlo a mano; después re-correr `down` |
| `check-orphans` falla | El destroy terminó pero quedó algo suelto: el log lista qué. Borrarlo desde la consola |
| Mail del budget o de anomalías | Revisar Cost Explorer filtrando por tag `project=facturacion` |

## 8. Después de la primera sesión

- Medir tiempos de `up` y `down` (doc 01) y el costo real contra el doc 02.
- Achicar los permisos de `gha-facturacion` con IAM Access Analyzer (doc 03).
- Revisar los hallazgos de Trivy y pasarlo a bloqueante.
