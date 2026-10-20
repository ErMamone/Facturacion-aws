#!/usr/bin/env bash

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
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: facturacion

resources:
  - ../../base

images:
  - name: facturacion-back
    newName: ${ECR_REGISTRY}/facturacion-back
    newTag: "${BACK_TAG}"
  - name: facturacion-web
    newName: ${ECR_REGISTRY}/facturacion-web
    newTag: "${WEB_TAG}"

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
