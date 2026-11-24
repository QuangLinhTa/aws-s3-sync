# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project: Containerized S3 Sync Service

**Main objective:** Build a containerized service that performs an operational task (S3 synchronization and compression) and exposes the result through a simple web server. Package and deploy it with modern tooling (Helm and Terraform on EKS).

The work is split into three parts, built in this order. Each part depends on the one before it.

## Repository layout (target)

```
.
├── CLAUDE.md
├── docker/                 # Part 1: image + script
│   ├── Dockerfile
│   ├── nginx.conf
│   └── scripts/sync.sh     # (or sync.py) core logic
├── helm/s3-sync/           # Part 2: Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
└── terraform/              # Part 3: reusable module
    └── modules/s3-sync/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── versions.tf
```

## Part 1: Docker image and automation script

**Goal:** One Docker image containing Nginx, AWS CLI, and a Bash/Python script that runs the core logic.

Requirements:
- A **single** Docker image.
- Must contain: **Nginx**, **AWS CLI**, and a **Bash or Python script**.
- The script performs the core logic: **S3 sync and compression**.
- Nginx serves the result (e.g. the compressed archive and/or a status page) over HTTP.

Guidelines:
- The script should download from S3 (`aws s3 sync`), compress the result (e.g. tar.gz), and place it in Nginx's web root.
- Configure it through environment variables (bucket, prefix, region, sync interval), never hard-coded values.
- Do not bake AWS credentials into the image. Use IAM roles (IRSA on EKS) or the default credential chain.
- The entrypoint starts the sync (run once, then optionally loop) and runs Nginx in the foreground.
- Use `set -euo pipefail` in Bash. Fail loudly and log to stdout/stderr.
- Keep the image small and run as non-root where practical.

## Part 2: Helm chart parameterization

**Goal:** Define the main configuration needed to deploy the container.

Requirements:
- The Deployment runs **multiple replicas** (parameterized via `replicaCount`).
- Each replica pod must be scheduled on a **different node**. Use pod anti-affinity (`requiredDuringSchedulingIgnoredDuringExecution`, topologyKey `kubernetes.io/hostname`) or topologySpreadConstraints.
- Pods deploy **only** on nodes in the node group labeled `test-nodes: true`. Use `nodeSelector` or required node affinity.

Guidelines:
- Everything configurable lives in `values.yaml`: image repo/tag, replicas, env vars (bucket, prefix, region), service type/port, resources, service account (with IRSA annotation), nodeSelector, affinity.
- Include Deployment, Service, and ServiceAccount templates at minimum.
- Validate with `helm lint` and `helm template` before considering it done.

## Part 3: Terraform EKS deployment

**Goal:** A reusable Terraform module that deploys the Part 2 Helm chart to a **pre-existing** EKS cluster.

Requirements:
- Must be a **reusable module** (inputs via variables, outputs exposed, no hard-coded environment values).
- Targets an **existing** EKS cluster. Look it up with `data "aws_eks_cluster"` and `data "aws_eks_cluster_auth"`. Do not create the cluster.
- Deploys the Helm chart from Part 2 using the `helm_release` resource.

Guidelines:
- Configure the `helm` provider from the existing cluster's endpoint, CA data, and auth token.
- Expose variables such as `cluster_name`, `region`, `namespace`, `release_name`, `chart_path`, `image`, `replica_count`, and passthrough `values`.
- Pin provider versions in `versions.tf`.
- Validate with `terraform fmt` and `terraform validate`.

## Working conventions

- Build and verify one part at a time. Do not start Part N+1 until Part N works.
- Do not commit secrets, credentials, or `.tfstate` files. Keep them in `.gitignore`.
- Keep the code simple and readable. Add comments only where intent is not obvious.
- Ask before running anything that touches real AWS resources, such as `terraform apply` or pushing images.

## Commands (once files exist)

```bash
# Part 1
docker build -t s3-sync:local docker/
docker run --rm -p 8080:80 -e S3_BUCKET=... s3-sync:local

# Part 2
helm lint helm/s3-sync
helm template s3-sync helm/s3-sync

# Part 3
cd terraform/modules/s3-sync && terraform fmt -check && terraform init -backend=false && terraform validate
```
