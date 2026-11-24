# Validates that the pre-existing cluster is reachable. The helm provider itself
# is configured by the caller (see examples/basic) using these same data sources.
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

locals {
  base_values = {
    replicaCount = var.replica_count
    image = {
      repository = var.image_repository
      tag        = var.image_tag
    }
    s3 = {
      bucket       = var.s3_bucket
      prefix       = var.s3_prefix
      region       = var.s3_region
      syncInterval = var.sync_interval
    }
    nodeSelector = var.node_selector
    serviceAccount = {
      annotations = var.service_account_role_arn == "" ? {} : {
        "eks.amazonaws.com/role-arn" = var.service_account_role_arn
      }
    }
  }
}

resource "helm_release" "this" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = true
  chart            = var.chart_path

  values = concat([yamlencode(local.base_values)], var.extra_values)

  # Ensure the cluster lookup succeeds before attempting the release.
  depends_on = [data.aws_eks_cluster.this]
}
