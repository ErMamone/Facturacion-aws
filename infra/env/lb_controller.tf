# AWS Load Balancer Controller: crea el ALB a partir de los Ingress.
# En Fargate no hay IMDS, así que region y vpcId van explícitos, y el
# target-type tiene que ser `ip`.
#
# OJO en el destroy: el ALB lo crea el controller, no OpenTofu. Antes de
# `tofu destroy` hay que borrar los Ingress y esperar a que el ALB desaparezca
# (doc 04, "Orden de down").

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

    # Tags en ALB, target groups y SG que crea el controller, para poder
    # filtrar en Cost Explorer por project=facturacion.
    defaultTags = {
      project = var.project
    }
  })]

  # Se instala después de los Fargate profiles y CoreDNS, y se desinstala
  # antes de borrar el cluster.
  depends_on = [module.eks]
}
