output "namespace" {
  description = "Kubernetes namespace where services are deployed"
  value       = kubernetes_namespace_v1.services.metadata[0].name
}

output "helm_release_status" {
  description = "Status of the Helm release"
  value       = helm_release.deploy_services.status
}

output "service_urls" {
  description = "Service URLs via Ingress"
  value = {
    fastify = "http://localhost/fastify/"
    nextjs  = "http://localhost/nextjs/"
    fastapi = "http://localhost/fastapi/"
  }
}
