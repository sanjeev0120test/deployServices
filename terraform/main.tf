resource "kubernetes_namespace" "services" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/part-of"    = "deploy-services"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "deploy_services" {
  name             = "deploy-services"
  chart            = var.helm_chart_path
  namespace        = kubernetes_namespace.services.metadata[0].name
  create_namespace = false
  wait             = true
  timeout          = 120

  set {
    name  = "fastifyService.image.tag"
    value = var.image_tag
  }

  set {
    name  = "fastifyService.replicaCount"
    value = var.fastify_replicas
  }

  set {
    name  = "nextjsService.image.tag"
    value = var.image_tag
  }

  set {
    name  = "nextjsService.replicaCount"
    value = var.nextjs_replicas
  }

  set {
    name  = "fastapiService.image.tag"
    value = var.image_tag
  }

  set {
    name  = "fastapiService.replicaCount"
    value = var.fastapi_replicas
  }
}
