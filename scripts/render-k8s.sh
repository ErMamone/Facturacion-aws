#!/usr/bin/env bash
# Genera k8s/overlays/demo/kustomization.yaml a partir de los outputs de
# `tofu output -json` del stack env. Ese overlay no se versiona.
#
# Uso: scripts/render-k8s.sh <outputs.json>
#
# Variables de entorno:
#   ECR_REGISTRY   <account>.dkr.ecr.<region>.amazonaws.com   (obligatoria)
#   BACK_TAG       tag de facturacion-back                      (default: latest)
#   WEB_TAG        tag de facturacion-web                       (default: latest)
#   APP_RETENTION  vida de cada factura, ISO-8601               (default: PT10M)
#
# Requiere: jq.

set -euo pipefail

OUTPUTS="${1:?Uso: $0 <outputs.json>}"
: "${ECR_REGISTRY:?Falta ECR_REGISTRY}"
BACK_TAG="${BACK_TAG:-latest}"
WEB_TAG="${WEB_TAG:-latest}"
APP_RETENTION="${APP_RETENTION:-PT10M}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/k8s/overlays/demo"

out() { jq -er --arg k "$1" '.[$k].value' "$OUTPUTS"; }

region=$(out region)
alb_sg=$(out alb_security_group_id)
bucket=$(out facturas_bucket)
rds_endpoint=$(out rds_endpoint)
db_name=$(out rds_db_name)
backend_role=$(out backend_irsa_role_arn)

mkdir -p "$OUT_DIR"
cat >"$OUT_DIR/kustomization.yaml" <<EOF
# GENERADO por scripts/render-k8s.sh. No editar ni commitear.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

images:
  - name: facturacion-back
    newName: ${ECR_REGISTRY}/facturacion-back
    newTag: "${BACK_TAG}"
  - name: facturacion-web
    newName: ${ECR_REGISTRY}/facturacion-web
    newTag: "${WEB_TAG}"

# Con hash en el nombre: si cambia la config, el Deployment se reinicia solo.
configMapGenerator:
  - name: facturacion-back
    literals:
      - SPRING_PROFILES_ACTIVE=prod
      - SPRING_DATASOURCE_URL=jdbc:postgresql://${rds_endpoint}/${db_name}
      - APP_BUCKET=${bucket}
      - AWS_REGION=${region}
      - APP_RETENTION=${APP_RETENTION}

patches:
  - target:
      kind: ServiceAccount
      name: facturacion-back
    patch: |-
      - op: replace
        path: /metadata/annotations/eks.amazonaws.com~1role-arn
        value: ${backend_role}
  - target:
      kind: Ingress
      name: facturacion
    patch: |-
      - op: replace
        path: /metadata/annotations/alb.ingress.kubernetes.io~1security-groups
        value: ${alb_sg}
EOF

echo "Overlay generado en ${OUT_DIR#"$ROOT"/}"
