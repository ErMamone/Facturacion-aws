# El ALB lo crea el controller: borrar los Ingress antes de tofu destroy (scripts/teardown.sh).
resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lb_controller_chart_version
  namespace  = "kube-system"

  values = [yamlencode({
    clusterName       = module.eks.cluster_name
    region            = var.region
    vpcId             = aws_vpc.this.id
    defaultTargetType = "ip"

    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = module.lb_controller_irsa.arn
      }
    }

    defaultTags = {
      project = var.project
    }
  })]

  depends_on = [module.eks]
}
