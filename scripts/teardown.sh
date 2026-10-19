#!/usr/bin/env bash
# Baja el stack env en el orden correcto (doc 04, "Orden de down"):
#   1. Borra los Ingress -> el LB Controller borra el ALB
#   2. Espera a que el ALB desaparezca
#   3. tofu destroy
#   4. check-orphans.sh
#
# Lo usan los workflows down y auto-destroy, y se puede correr a mano.
# Requiere: aws CLI, kubectl y tofu, con credenciales que tengan acceso al
# cluster (access entry) y al bucket de state.

set -euo pipefail

CLUSTER="${CLUSTER:-facturacion}"
NAMESPACE="${NAMESPACE:-facturacion}"
ALB_NAME="${ALB_NAME:-facturacion}"
REGION="${AWS_REGION:-us-east-1}"

export AWS_REGION="$REGION"
export AWS_PAGER=""

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_DIR="$ROOT/infra/env"

account=$(aws sts get-caller-identity --query Account --output text)

echo "==> 1/4 Borrando Ingress"
if aws eks describe-cluster --name "$CLUSTER" >/dev/null 2>&1; then
  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null
  if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    # --wait espera el finalizer del controller, que se quita al borrar el ALB.
    kubectl delete ingress --all -n "$NAMESPACE" --wait=true --timeout=10m
  else
    echo "    No existe el namespace $NAMESPACE"
  fi
else
  echo "    No existe el cluster $CLUSTER"
fi

echo "==> 2/4 Esperando que no quede el ALB $ALB_NAME"
for _ in $(seq 1 60); do
  if ! aws elbv2 describe-load-balancers --names "$ALB_NAME" >/dev/null 2>&1; then
    echo "    ALB borrado"
    break
  fi
  sleep 10
done
if aws elbv2 describe-load-balancers --names "$ALB_NAME" >/dev/null 2>&1; then
  echo "ERROR: el ALB $ALB_NAME sigue existiendo después de 10 minutos. No se corre destroy." >&2
  exit 1
fi

echo "==> 3/4 tofu destroy"
tofu -chdir="$ENV_DIR" init -input=false -backend-config="bucket=facturacion-tfstate-${account}"
tofu -chdir="$ENV_DIR" destroy -input=false -auto-approve

echo "==> 4/4 Buscando huérfanos"
"$ROOT/scripts/check-orphans.sh" "$CLUSTER" "$REGION"
