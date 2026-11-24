# S3 Sync Service

Syncs an S3 prefix, compresses it to `archive.tar.gz`, and serves it (plus `status.json`) via Nginx on port 8080.

## 1. Build the image
```bash
docker build -t s3-sync:local docker/
docker run --rm -p 8080:8080 -e S3_BUCKET=my-bucket -e AWS_REGION=us-east-1 s3-sync:local
curl localhost:8080/status.json
```
Env vars: `S3_BUCKET` (required), `S3_PREFIX`, `AWS_REGION`, `SYNC_INTERVAL` (seconds, default 300).

Push to ECR before deploying to EKS (`docker tag` + `docker push <account>.dkr.ecr.<region>.amazonaws.com/s3-sync:<tag>`).

## 2. Helm chart
```bash
helm lint helm/s3-sync --set s3.bucket=my-bucket
helm template s3-sync helm/s3-sync --set s3.bucket=my-bucket
```
Defaults: 3 replicas, `nodeSelector: test-nodes=true`, required pod anti-affinity on `kubernetes.io/hostname`.
For S3 access, annotate the ServiceAccount with an IRSA role ARN (`serviceAccount.annotations`).

## 3. Terraform module
`terraform/modules/s3-sync` deploys the chart to an existing EKS cluster. The caller configures the `helm` provider; see `terraform/examples/basic`.
```bash
cd terraform/examples/basic
terraform init
terraform plan -var cluster_name=... -var region=... -var s3_bucket=... -var image_repository=...
```
