# S3 Sync Service

Syncs an S3 prefix, compresses it to `archive.tar.gz`, and serves it (plus `status.json`) via Nginx on port 8080.

## 1. Build the image
```bash
docker build -t s3-sync:local docker/
docker run --rm -p 8080:8080 -e S3_BUCKET=my-bucket -e AWS_REGION=us-east-1 s3-sync:local
curl localhost:8080/status.json
```
Env vars: `S3_BUCKET` (required), `S3_PREFIX`, `AWS_REGION`, `SYNC_INTERVAL` (seconds, default 300).

### Loop mode and sync interval
Loop mode is the default. The entrypoint starts `sync.py loop` in the background (sync, compress, publish, sleep `SYNC_INTERVAL` seconds, repeat) and runs Nginx in the foreground. A failed sync is logged, `status.json` reports `failure`, and the loop retries on the next cycle.
```bash
docker run --rm -p 8080:8080 -e SYNC_INTERVAL=60 -e S3_BUCKET=my-bucket -e AWS_REGION=us-east-1 s3-sync:local
```
The interval is the sleep after each run, so the real cycle is sync time plus the interval. In Helm set `s3.syncInterval`; in Terraform set `sync_interval`.

To test a single sync, bypass the entrypoint with `once` mode. It exits 0 on success and 1 on failure, and does not start Nginx:
```bash
docker run --rm --entrypoint python3 -e S3_BUCKET=my-bucket -e AWS_REGION=us-east-1 \
  s3-sync:local /usr/local/bin/sync.py once
```

### Running locally with AWS SSO (no long-term credentials)
The container can't see your host's `~/.aws` profile, and the cached SSO token usually can't be refreshed from inside it. Export short-lived credentials and pass them in as environment variables instead:
```bash
# 1. Log in (re-run when the session expires)
aws sso login --profile my-sso-profile

# 2. Export short-lived credentials into your shell
eval "$(aws configure export-credentials --profile my-sso-profile --format env)"

# 3. Pass them to the container
docker run --rm -p 8080:8080 \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
  -e AWS_REGION=us-east-1 -e S3_BUCKET=my-bucket \
  s3-sync:local
```
- Your SSO role needs `s3:ListBucket` on the bucket and `s3:GetObject` on its objects.
- The credentials expire (typically 1 to 12 hours). Once they do, `status.json` reports `failure`. To refresh, run `aws sso login` again, re-export, and restart the container.
- Check the login with `aws sts get-caller-identity --profile my-sso-profile`.
- On EKS the pod doesn't use SSO. It gets temporary credentials through IRSA (see the Helm section).

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
