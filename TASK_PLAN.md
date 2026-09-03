# Implementation Task Plan

This checklist builds the Containerized S3 Sync Service from an empty repository. Complete the stages in order. Each stage has a concrete output and a check that should pass before continuing.

## Success criteria

The project is complete when all of the following are true:

- One Docker image contains Nginx, AWS CLI, the sync script, and compression tools.
- The service periodically runs `aws s3 sync`, creates a `.tar.gz`, and serves the latest successful archive.
- Failed refreshes preserve the previous archive.
- Helm deploys multiple replicas only to nodes labeled `test-nodes=true`.
- Required anti-affinity prevents two replicas from sharing a node.
- Terraform installs the chart into an existing EKS cluster.
- AWS access uses IRSA or an explicitly supplied existing service-account role.
- Local tests and static validation pass.

## Stage 0: Confirm tools and repository

- [ ] Confirm the working directory is the repository root.
- [ ] Install or verify Docker, Bash, AWS CLI, Helm, `kubectl`, and Terraform.
- [ ] Create the planned directories: `scripts/`, `nginx/`, `deploy/helm/s3-sync-service/`, `terraform/modules/s3-sync-service/`, `terraform/examples/existing-eks/`, and `tests/`.
- [ ] Decide the image registry and tag convention.
- [ ] Decide the source S3 bucket/prefix and AWS region.

Check:

```bash
pwd
command -v docker bash aws helm kubectl terraform
```

Expected result: every required command is available, or the missing tool is installed before continuing.

## Stage 1: Implement the sync worker

- [ ] Create `scripts/sync-and-serve.sh` with strict Bash settings.
- [ ] Validate `SOURCE_S3_URI` and `AWS_REGION`.
- [ ] Set defaults for interval, archive name, working directory, and output directory.
- [ ] Start Nginx and keep its PID available for shutdown handling.
- [ ] Implement one sync cycle with `aws s3 sync`.
- [ ] Compress the synchronized directory with `tar` and `gzip`.
- [ ] Write to a temporary archive in the output directory.
- [ ] Atomically rename the temporary archive to the configured final name.
- [ ] Create a readiness marker only after the first successful publication.
- [ ] Continue retrying after failures without deleting the last successful archive.
- [ ] Trap termination signals and stop the child Nginx process cleanly.

Check:

```bash
bash -n scripts/sync-and-serve.sh
```

Expected result: the script passes shell syntax validation.

## Stage 2: Configure Nginx

- [ ] Create `nginx/nginx.conf`.
- [ ] Serve the output directory as static content.
- [ ] Add `/healthz` for process-level health.
- [ ] Add `/ready` that returns success only when the readiness marker exists.
- [ ] Use a non-privileged listen port such as `8080`.
- [ ] Disable directory behavior that could expose unintended files.

Check:

```bash
nginx -t -c "$PWD/nginx/nginx.conf" -p "$PWD"
```

Expected result: Nginx accepts the configuration. If Nginx is not installed locally, perform this check during the Docker smoke test.

## Stage 3: Build the single Docker image

- [ ] Choose a base image that supports Nginx, AWS CLI, Bash, and compression tools.
- [ ] Install only required runtime packages.
- [ ] Copy the worker and Nginx configuration into the image.
- [ ] Create writable work/output directories.
- [ ] Expose the Nginx port.
- [ ] Add a container health check for `/healthz`.
- [ ] Run as a non-root user where compatible with Nginx and AWS CLI.
- [ ] Add `.dockerignore` for Git metadata, test artifacts, and local credentials.

Checks:

```bash
docker build -t s3-sync-service:test .
docker image inspect s3-sync-service:test
```

Expected result: one image builds successfully and contains the worker, Nginx, AWS CLI, and archive tools.

## Stage 4: Add worker and container tests

- [ ] Create a fake `aws` executable for tests.
- [ ] Test missing required configuration.
- [ ] Test the `aws s3 sync` command arguments.
- [ ] Test successful archive publication.
- [ ] Test that a failed cycle leaves an existing archive untouched.
- [ ] Test that temporary archive files are not served after a failed compression.
- [ ] Test readiness before and after the first successful cycle.
- [ ] Run a Docker smoke test that confirms Nginx serves the archive and health paths.

Checks:

```bash
bash tests/sync-and-serve.test.sh
docker run --rm s3-sync-service:test --help
```

Expected result: all focused tests pass. Adjust the smoke-test command to the final image interface once implemented.

## Stage 5: Create the Helm chart

- [ ] Add `Chart.yaml`.
- [ ] Add documented defaults in `values.yaml`.
- [ ] Add helper templates and consistent application labels.
- [ ] Create the Deployment with configurable replica count.
- [ ] Add `nodeSelector.test-nodes: "true"`.
- [ ] Add required pod anti-affinity against the application label.
- [ ] Set anti-affinity `topologyKey` to `kubernetes.io/hostname`.
- [ ] Add `emptyDir` storage for work/output data.
- [ ] Add readiness and liveness probes.
- [ ] Add configurable resources, security context, and image settings.
- [ ] Add a Service for the Nginx port.
- [ ] Add a ServiceAccount with configurable annotations.
- [ ] Support IRSA annotations and existing Secret references without committing credentials.
- [ ] Add a PodDisruptionBudget if the availability policy requires one.

Checks:

```bash
helm lint deploy/helm/s3-sync-service
helm template s3-sync-service deploy/helm/s3-sync-service \
  --set image.repository=example/s3-sync \
  --set image.tag=test \
  --set s3.sourceUri=s3://example/source/ \
  --set aws.region=us-east-1
```

Expected result: lint passes, and rendered YAML contains the node selector, required hostname anti-affinity, multiple replicas, probes, volume, and ServiceAccount configuration.

## Stage 6: Test scheduling and chart behavior

- [ ] Add chart tests or render assertions for default and custom replica counts.
- [ ] Assert the node selector is exactly `test-nodes: "true"`.
- [ ] Assert anti-affinity is required rather than preferred.
- [ ] Assert the topology key is `kubernetes.io/hostname`.
- [ ] Assert the Service selector matches the Deployment labels.
- [ ] Assert the IRSA annotation is rendered when supplied.
- [ ] Assert credentials are not present in rendered output by default.

Checks:

```bash
helm template s3-sync-service deploy/helm/s3-sync-service > /tmp/s3-sync-rendered.yaml
rg -n "test-nodes|kubernetes.io/hostname|podAntiAffinity|readinessProbe|livenessProbe" /tmp/s3-sync-rendered.yaml
```

Expected result: all required scheduling and operational settings are visible in the rendered manifests.

## Stage 7: Implement the Terraform module

- [ ] Create module variables for existing cluster name, region, namespace, release, chart path, image, S3 source, interval, replicas, and optional Helm values.
- [ ] Add variable validation for non-empty names, valid replica count, and required S3 configuration.
- [ ] Add EKS data sources for cluster and OIDC information where needed.
- [ ] Add configurable namespace creation.
- [ ] Add configurable service-account ownership.
- [ ] Create an IRSA role and trust policy by default.
- [ ] Restrict the IAM policy to the configured S3 bucket and prefix.
- [ ] Allow a pre-existing role/service account when platform IAM is externally managed.
- [ ] Install the Helm chart with `helm_release`.
- [ ] Pass chart values without embedding static credentials.
- [ ] Add useful outputs for release, namespace, service account, and role.
- [ ] Add an example root configuration under `terraform/examples/existing-eks/`.

Checks:

```bash
terraform -chdir=terraform/modules/s3-sync-service fmt -check
terraform -chdir=terraform/modules/s3-sync-service init
terraform -chdir=terraform/modules/s3-sync-service validate
terraform -chdir=terraform/examples/existing-eks fmt -check
terraform -chdir=terraform/examples/existing-eks validate
```

Expected result: formatting and validation pass without requiring an apply to AWS.

## Stage 8: Deploy to an existing EKS cluster

- [ ] Confirm the EKS cluster exists and the provider can authenticate.
- [ ] Confirm the cluster has an OIDC provider for IRSA.
- [ ] Confirm enough nodes are labeled `test-nodes=true`.
- [ ] Build and push the image to the selected registry.
- [ ] Apply the Terraform module or install the Helm chart.
- [ ] Wait for the Deployment and inspect events.
- [ ] Confirm every ready Pod is on a different node.
- [ ] Confirm the ServiceAccount has the expected role annotation.
- [ ] Confirm the worker can list/read the configured S3 prefix.
- [ ] Confirm Nginx serves the archive.

Checks:

```bash
kubectl get nodes -l test-nodes=true -o wide
kubectl -n s3-sync get pods -o wide
kubectl -n s3-sync get serviceaccount -o yaml
kubectl -n s3-sync logs deploy/s3-sync-service
kubectl -n s3-sync port-forward svc/s3-sync-service 8080:8080
curl -f http://127.0.0.1:8080/healthz
curl -f http://127.0.0.1:8080/ready
```

Expected result: all replicas are ready, located on distinct eligible nodes, and serving the latest successful archive.

## Stage 9: Failure and operational verification

- [ ] Temporarily deny or remove access to the source prefix.
- [ ] Confirm the worker logs the failure and continues retrying.
- [ ] Confirm the previous archive remains downloadable.
- [ ] Restore access and confirm the next successful cycle replaces the archive atomically.
- [ ] Confirm liveness remains healthy during a temporary S3 outage.
- [ ] Confirm readiness remains meaningful before the first successful archive.
- [ ] Confirm rolling updates do not create unintended co-location.

Expected result: transient S3 failures do not erase the last known-good output or cause needless Pod restarts.

## Stage 10: Documentation and release readiness

- [ ] Keep `README.md` configuration and commands synchronized with the implementation.
- [ ] Document required S3 permissions and the IRSA trust relationship.
- [ ] Document the node label prerequisite and anti-affinity behavior.
- [ ] Document image build, Helm, Terraform, troubleshooting, and cleanup.
- [ ] Add CI checks for shell tests, Docker build, Helm lint/template, and Terraform fmt/validate.
- [ ] Run all local checks from a clean working tree.
- [ ] Record the image tag and chart version used for the deployment.

Final verification:

```bash
bash -n scripts/sync-and-serve.sh
helm lint deploy/helm/s3-sync-service
terraform -chdir=terraform/modules/s3-sync-service fmt -check
terraform -chdir=terraform/modules/s3-sync-service validate
git status --short
```

Completion means the success criteria at the top of this document are demonstrably satisfied, not merely that the manifests render.
