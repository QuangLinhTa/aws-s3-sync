terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12, < 3.0"
    }
  }
}

variable "cluster_name" { type = string }
variable "region" { type = string }
variable "s3_bucket" { type = string }
variable "image_repository" { type = string }

provider "aws" {
  region = var.region
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

module "s3_sync" {
  source = "../../modules/s3-sync"

  cluster_name     = var.cluster_name
  chart_path       = "${path.module}/../../../helm/s3-sync"
  image_repository = var.image_repository
  image_tag        = "latest"
  s3_bucket        = var.s3_bucket
  s3_region        = var.region
}
