# Containerized S3 Sync Service

A single-container service that periodically synchronizes an S3 prefix, compresses the synchronized files into a `.tar.gz` archive, and serves the latest successful archive through Nginx.

The service is designed for deployment to an existing Amazon EKS cluster using Helm and Terraform.

## Architecture

```text
S3 source bucket/prefix
        |
        v
AWS CLI sync worker -> local working directory -> atomic archive publish
                                                        |
                                                        v
                                                     Nginx
                                                        |
                                                        v
                                             Kubernetes Service / HTTP client
```

Each replica runs the worker and Nginx in the same container. Each Pod has its own temporary working directory. S3 is the shared source of truth, so no shared filesystem is required.

## Target repository layout

```text
.
├── Dockerfile
├── nginx/nginx.conf
├── scripts/sync-and-serve.sh
├── deploy/helm/s3-sync-service/
├── terraform/modules/s3-sync-service/
├── terraform/examples/existing-eks/
├── tests/
├── README.md
└── TASK_PLAN.md
```

## Prerequisites

For local work:

- Docker
- Bash
- AWS CLI credentials with access to the source bucket

For Kubernetes deployment:

- `kubectl`
- Helm 3
- An existing EKS cluster
- At least as many eligible `test-nodes=true` nodes as the configured replica count
- Nodes labeled with:

  ```bash
  kubectl label node <node-name> test-nodes=true
  ```

For Terraform deployment:

- Terraform 1.5 or newer
- AWS provider credentials
- Helm provider access to the existing EKS cluster
- An EKS OIDC provider enabled for IRSA

## Configuration

The container should receive configuration through environment variables or Helm values. Static AWS access keys must not be committed to the repository.

| Variable | Required | Example | Description |
|---|---:|---|---|
| `SOURCE_S3_URI` | yes | `s3://my-source/input/` | S3 bucket and prefix to synchronize |
| `AWS_REGION` | yes | `us-east-1` | AWS region |
| `SYNC_INTERVAL_SECONDS` | no | `3600` | Delay between successful or failed sync attempts |
| `ARCHIVE_NAME` | no | `s3-sync.tar.gz` | Name served by Nginx |
| `WORK_DIR` | no | `/var/lib/s3-sync/work` | Temporary sync directory |
| `OUTPUT_DIR` | no | `/var/lib/s3-sync/output` | Directory containing the published archive |

The worker should validate required values before starting. A sync cycle should use a temporary archive and rename it into place only after compression succeeds. If a later cycle fails, the previous successful archive remains available.

## Required AWS permissions

The recommended production setup uses IRSA. The service account role should receive only the required S3 permissions, scoped to the configured bucket and prefix:

- `s3:ListBucket` on the source bucket, restricted by prefix where possible
- `s3:GetObject` on the source prefix

If an optional destination upload is implemented later, add only the required `s3:PutObject` permission for that destination prefix.

Do not use long-lived access keys in Kubernetes Secrets unless IRSA is unavailable and the security team explicitly approves that approach.

## Build and run locally

Build the single image after the implementation is complete:

```bash
docker build -t s3-sync-service:dev .
```

Run it with AWS credentials supplied by the local environment:

```bash
docker run --rm \
  -p 8080:8080 \
  -e AWS_REGION=us-east-1 \
  -e SOURCE_S3_URI=s3://my-source/input/ \
  -e SYNC_INTERVAL_SECONDS=3600 \
  -e ARCHIVE_NAME=s3-sync.tar.gz \
  s3-sync-service:dev
```

The exact Nginx port and health paths should remain consistent between the Dockerfile, Nginx configuration, Helm Service, and probes. The expected endpoints are:

- `GET /healthz`: process-level health
- `GET /ready`: successful first archive publication
- `GET /s3-sync.tar.gz`: latest successful archive

## Helm deployment

Render and validate the chart before installing:

```bash
helm lint deploy/helm/s3-sync-service
helm template s3-sync-service deploy/helm/s3-sync-service \
  --namespace s3-sync \
  --set image.repository=REPLACE_ME \
  --set image.tag=REPLACE_ME \
  --set s3.sourceUri=s3://my-source/input/ \
  --set aws.region=us-east-1
```

Install or upgrade it into the existing cluster:

```bash
helm upgrade --install s3-sync-service deploy/helm/s3-sync-service \
  --namespace s3-sync \
  --create-namespace \
  --set image.repository=REPLACE_ME \
  --set image.tag=REPLACE_ME \
  --set s3.sourceUri=s3://my-source/input/ \
  --set aws.region=us-east-1 \
  --set serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=REPLACE_WITH_IRSA_ROLE_ARN
```

The chart must configure:

- `nodeSelector: { test-nodes: "true" }`
- Required pod anti-affinity with `topologyKey: kubernetes.io/hostname`
- Multiple replicas
- Readiness and liveness probes
- A writable `emptyDir` volume

Required anti-affinity intentionally leaves Pods pending when there are not enough eligible nodes. This enforces the requirement that replicas do not share a node.

Check placement and service status:

```bash
kubectl -n s3-sync get pods -o wide
kubectl -n s3-sync get svc
kubectl -n s3-sync describe pod <pod-name>
```

## Terraform deployment

The Terraform module deploys the Helm chart to a pre-existing EKS cluster. It must not create the cluster or its node groups.

A typical root module should configure AWS and Helm providers, then call:

```hcl
module "s3_sync" {
  source = "../../modules/s3-sync-service"

  cluster_name       = var.cluster_name
  aws_region         = var.aws_region
  release_name       = "s3-sync-service"
  namespace          = "s3-sync"
  chart_path         = "${path.module}/../../../deploy/helm/s3-sync-service"
  image_repository   = var.image_repository
  image_tag          = var.image_tag
  source_s3_uri      = "s3://my-source/input/"
  replica_count      = 3
  create_irsa_role   = true
}
```

Run validation and inspect the plan:

```bash
terraform fmt -check -recursive
terraform init
terraform validate
terraform plan
```

The module should create an IRSA role and least-privilege policy by default, while allowing platform-managed IAM roles as an alternative. Provider authentication details remain the responsibility of the Terraform root module or execution environment.

## Operations and failure behavior

- A successful cycle replaces the archive atomically.
- A failed cycle is logged and does not delete the previous successful archive.
- Before the first successful cycle, readiness should remain false.
- Liveness should describe process health, not S3 availability, so a temporary S3 outage does not cause unnecessary restarts.
- Each replica independently refreshes its local archive. Clients may briefly receive different successful versions from different replicas during an update cycle.

For exactly-once synchronization, replace the Deployment worker loop with a separate CronJob or leader-election design. That is a different operating model from this service-oriented design.

## Troubleshooting

Inspect logs:

```bash
kubectl -n s3-sync logs deploy/s3-sync-service
```

If Pods are pending, verify both node capacity and labels:

```bash
kubectl get nodes -l test-nodes=true
kubectl -n s3-sync describe pod <pod-name>
```

If AWS access fails, verify the service account annotation, the role trust policy, the EKS OIDC provider, region, bucket, and prefix permissions:

```bash
kubectl -n s3-sync get serviceaccount -o yaml
```

If readiness stays false, inspect the worker log and verify that the source prefix exists and the archive output directory is writable.

## Cleanup

Remove the Helm release and namespace:

```bash
helm uninstall s3-sync-service --namespace s3-sync
kubectl delete namespace s3-sync
```

When Terraform created the IRSA role, remove it through Terraform after confirming no other workload uses it.

## Implementation checklist

Follow [TASK_PLAN.md](TASK_PLAN.md) in order. It includes dependencies, commands, expected outcomes, and acceptance criteria for each milestone.
