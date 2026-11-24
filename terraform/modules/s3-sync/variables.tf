variable "cluster_name" {
  description = "Name of the pre-existing EKS cluster (used for lookup only; the module never creates it)."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into."
  type        = string
  default     = "s3-sync"
}

variable "release_name" {
  description = "Helm release name."
  type        = string
  default     = "s3-sync"
}

variable "chart_path" {
  description = "Path to the s3-sync Helm chart."
  type        = string
}

variable "replica_count" {
  description = "Number of replicas (each lands on a different node)."
  type        = number
  default     = 3
}

variable "image_repository" {
  description = "Container image repository (e.g. an ECR URL)."
  type        = string
}

variable "image_tag" {
  description = "Container image tag."
  type        = string
  default     = "latest"
}

variable "s3_bucket" {
  description = "S3 bucket to sync from."
  type        = string
}

variable "s3_prefix" {
  description = "S3 key prefix to sync."
  type        = string
  default     = ""
}

variable "s3_region" {
  description = "AWS region of the bucket."
  type        = string
  default     = "us-east-1"
}

variable "sync_interval" {
  description = "Seconds between syncs."
  type        = number
  default     = 300
}

variable "service_account_role_arn" {
  description = "IAM role ARN for IRSA, granting S3 read access. Empty to skip the annotation."
  type        = string
  default     = ""
}

variable "node_selector" {
  description = "Node selector restricting where pods run."
  type        = map(string)
  default     = { "test-nodes" = "true" }
}

variable "extra_values" {
  description = "Additional raw YAML values passed to the chart (merged last)."
  type        = list(string)
  default     = []
}
