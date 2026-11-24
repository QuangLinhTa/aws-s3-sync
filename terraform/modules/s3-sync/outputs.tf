output "release_name" {
  description = "Name of the Helm release."
  value       = helm_release.this.name
}

output "namespace" {
  description = "Namespace the release was installed into."
  value       = helm_release.this.namespace
}

output "status" {
  description = "Helm release status."
  value       = helm_release.this.status
}
