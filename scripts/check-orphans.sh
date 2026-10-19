#!/usr/bin/env bash

set -euo pipefail

CLUSTER="${1:-facturacion}"
REGION="${2:-${AWS_REGION:-us-east-1}}"
PROJECT_TAG="${PROJECT_TAG:-facturacion}"

export AWS_REGION="$REGION"
export AWS_PAGER=""

found=0

report() {
  local title="$1" items="$2"
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

lb_arns=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' --output text)
orphan_lbs=""
if [[ -n "$lb_arns" && "$lb_arns" != "None" ]]; then
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

report "NAT Gateways" "$(aws ec2 describe-nat-gateways \
  --filter "Name=tag:project,Values=$PROJECT_TAG" "Name=state,Values=pending,available" \
  --query 'NatGateways[].NatGatewayId' --output text)"

report "Elastic IPs sin asociar" "$(aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==null].AllocationId' --output text)"

report "ENIs disponibles" "$(aws ec2 describe-network-interfaces \
  --filters "Name=status,Values=available" \
  --query 'NetworkInterfaces[].NetworkInterfaceId' --output text)"

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

report "CloudWatch log groups" "$(aws logs describe-log-groups \
  --log-group-name-prefix "/aws/eks/$CLUSTER" \
  --query 'logGroups[].logGroupName' --output text)"

echo
if [[ "$found" -ne 0 ]]; then
  echo "Se encontraron recursos huérfanos. Revisarlos y borrarlos a mano."
  exit 1
fi
echo "Sin huérfanos."
