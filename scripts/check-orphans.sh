#!/usr/bin/env bash
# Busca recursos que siguen cobrando (o bloquean el próximo destroy) después de
# `tofu destroy` del stack env. Sale con código 1 si encuentra algo.
#
# Uso: scripts/check-orphans.sh [cluster_name] [region]
#   cluster_name: default "facturacion"
#   region:       default $AWS_REGION, o us-east-1
#
# Requiere: aws CLI v2 con credenciales de la cuenta.

set -euo pipefail

CLUSTER="${1:-facturacion}"
REGION="${2:-${AWS_REGION:-us-east-1}}"
PROJECT_TAG="${PROJECT_TAG:-facturacion}"

export AWS_REGION="$REGION"
export AWS_PAGER=""

found=0

report() {
  local title="$1" items="$2"
  # La CLI devuelve "None" o vacío cuando no hay resultados.
  if [[ -n "$items" && "$items" != "None" ]]; then
    echo "ORPHAN  $title:"
    echo "$items" | tr '\t' '\n' | sed 's/^/          /'
    found=1
  else
    echo "ok      $title"
  fi
}

echo "Buscando huérfanos de cluster=$CLUSTER project=$PROJECT_TAG en $REGION"
echo

# 1. Load balancers (ALB/NLB) creados por el LB Controller para este cluster,
#    o con el tag del proyecto.
lb_arns=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' --output text)
orphan_lbs=""
if [[ -n "$lb_arns" && "$lb_arns" != "None" ]]; then
  # describe-tags acepta hasta 20 ARNs por llamada.
  read -r -a arr <<<"$lb_arns"
  for ((i = 0; i < ${#arr[@]}; i += 20)); do
    batch=("${arr[@]:i:20}")
    matches=$(aws elbv2 describe-tags --resource-arns "${batch[@]}" \
      --query "TagDescriptions[?Tags[?(Key=='elbv2.k8s.aws/cluster' && Value=='$CLUSTER') || (Key=='project' && Value=='$PROJECT_TAG')]].ResourceArn" \
      --output text)
    [[ -n "$matches" && "$matches" != "None" ]] && orphan_lbs+="$matches"$'\t'
  done
fi
report "Load balancers" "${orphan_lbs%$'\t'}"

# 2. NAT Gateways vivos del proyecto.
report "NAT Gateways" "$(aws ec2 describe-nat-gateways \
  --filter "Name=tag:project,Values=$PROJECT_TAG" "Name=state,Values=pending,available" \
  --query 'NatGateways[].NatGatewayId' --output text)"

# 3. Elastic IPs sin asociar (cobran igual). Se revisan todas, no solo las del proyecto.
report "Elastic IPs sin asociar" "$(aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==null].AllocationId' --output text)"

# 4. ENIs en estado available (sueltas). Bloquean el borrado de subnets/SG.
report "ENIs disponibles" "$(aws ec2 describe-network-interfaces \
  --filters "Name=status,Values=available" \
  --query 'NetworkInterfaces[].NetworkInterfaceId' --output text)"

# 5. Security groups con tag del cluster (LB Controller / EKS) o del proyecto.
sgs=""
for filter in \
  "Name=tag:elbv2.k8s.aws/cluster,Values=$CLUSTER" \
  "Name=tag-key,Values=kubernetes.io/cluster/$CLUSTER" \
  "Name=tag:project,Values=$PROJECT_TAG"; do
  ids=$(aws ec2 describe-security-groups --filters "$filter" --query 'SecurityGroups[].GroupId' --output text)
  [[ -n "$ids" && "$ids" != "None" ]] && sgs+="$ids"$'\t'
done
sgs=$(echo -n "${sgs%$'\t'}" | tr '\t' '\n' | sort -u | paste -sd $'\t' -)
report "Security groups" "$sgs"

# 6. Log groups del cluster.
report "CloudWatch log groups" "$(aws logs describe-log-groups \
  --log-group-name-prefix "/aws/eks/$CLUSTER" \
  --query 'logGroups[].logGroupName' --output text)"

echo
if [[ "$found" -ne 0 ]]; then
  echo "Se encontraron recursos huérfanos. Revisarlos y borrarlos a mano."
  exit 1
fi
echo "Sin huérfanos."
