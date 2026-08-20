# DevOps Challenge — CI/CD and Terraform for rdiCidr

This document describes the infrastructure and CI/CD pipelines built on top of the `rdiCidr` application as part of the FullStack Labs technical challenge (DevOps / AWS / Terraform). It does not replace the original `README.md` (which describes the app itself) — this one covers the DevOps work exclusively.

## Overview

The goal was to automate the full integration and deployment cycle of the `rdiCidr` React app to AWS, with two isolated environments (`devel` and `stage`), following a strict branching strategy and without using any autocomplete or AI-assisted tooling during the build.

## Branching strategy

- `feature/*` (or `fix/*`, `bugfix/*`) → Pull Request → `devel`
- `devel` → Pull Request → `stage`
- Direct pushes to `devel` or `stage` are not allowed.
- A **Branch Guard** workflow (`.github/workflows/branch-guard.yaml`) blocks any Pull Request into `stage` whose source branch isn't exactly `devel`, preventing the `feature → devel → stage` flow from being skipped.

## Continuous Integration pipeline (CI)

File: `.github/workflows/ci.yaml`

Triggers on every Pull Request targeting `devel` or `stage`. Runs on `ubuntu-latest` and executes, in order:

1. Checkout the code
2. Set up Node.js (v15, the version required by `react-scripts@4`)
3. Install dependencies (`npm install --legacy-peer-deps`, needed due to peer dependency conflicts between Babel and `react-scripts`)
4. Lint (`npm run lint`)
5. Tests (`npm run test`, with `CI=true` so it doesn't stay in watch mode)
6. Production build (`npm run build`)

If any of these steps fails, the PR is blocked — it's a required check before merging.

## Continuous Deployment pipeline (CD)

File: `.github/workflows/cd.yaml`

Triggers on every `push` (i.e. every merge) directly to `devel` or `stage` — never on Pull Requests, so deployment only happens once the code has actually landed on the branch.

Steps:

1. Checkout the code
2. Set up Node.js and build the app (`npm run build`)
3. Configure AWS credentials (from GitHub Secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
4. Set up Terraform (v1.9.8)
5. `terraform init`
6. Select/create the Terraform workspace based on the branch (`terraform workspace select $branch || terraform workspace new $branch`) — this keeps `devel` and `stage` in fully separate workspaces (and therefore separate states)
7. `terraform apply -auto-approve` using the matching `.tfvars` file for the environment (`terraform/environments/devel.tfvars` or `stage.tfvars`)
8. Sync the build output (`npm run build`) to the site's S3 bucket (`aws s3 sync`)
9. Invalidate the CloudFront cache, so the new content is visible immediately
10. Print the public URL of the environment that was just deployed

## Infrastructure (Terraform)

Files under `terraform/`: `main.tf`, `providers.tf`, `variables.tf`, `outputs.tf`, `environments/devel.tfvars`, `environments/stage.tfvars`.

Requires Terraform `>= 1.5.0` and the AWS provider `~> 5.0`.

Main resources:

- **`aws_s3_bucket.site`** — private bucket (with `force_destroy`, versioning, and SSE-AES256 encryption) that stores the app build. No direct public access: everything goes through CloudFront.
- **`aws_s3_bucket.logs`** — separate bucket for CloudFront access logs, with an ACL configured to allow AWS's log delivery service (`awslogsdelivery`) to write to it, ownership controls set to `BucketOwnerPreferred`, and a lifecycle rule that expires logs after 30 days.
- **`aws_cloudfront_origin_access_control` + `aws_cloudfront_distribution.site`** — CloudFront distribution that serves the site from the private bucket using Origin Access Control (OAC, the modern replacement for OAI), with SPA routing handled (403/404 redirect to `index.html` so React Router works) and logging enabled to the logs bucket.
- **`aws_s3_bucket_policy.site`** (via `data.aws_iam_policy_document`) — policy that allows CloudFront (and only the distribution created by this Terraform, via a `StringEquals` condition on the distribution's ARN) to read objects from the bucket.
- **`random_id.suffix`** — random suffix used in all resource names (`local.name_prefix = "${var.app_name}-${var.environment}-${random_id.suffix.hex}"`) to avoid naming collisions between runs.

### Environment isolation

`devel` and `stage` are managed as **separate Terraform workspaces**, each with its own state and its own `.tfvars` file (`terraform/environments/devel.tfvars` and `stage.tfvars`), ensuring the infrastructure of one environment never interferes with the other.

### Variables (`variables.tf`)

| Variable | Description | Default |
|---|---|---|
| `environment` | `devel` or `stage` (validated) | — |
| `aws_region` | AWS region | `us-east-1` |
| `app_name` | Prefix used to name resources | `rdicidr` |

### Outputs (`outputs.tf`)

- `site_bucket_name`
- `logs_bucket_name`
- `cloudfront_distribution_id`
- `cloudfront_domain_name`

## Required GitHub secrets

Configured under **Settings → Secrets and variables → Actions** on the repository:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

## Manual deployment (outside the pipeline)

```bash
cd terraform
terraform init
terraform workspace select devel || terraform workspace new devel
terraform apply -var-file="environments/devel.tfvars"
```

Repeat with `stage` and `stage.tfvars` for that environment.

## Tearing down the infrastructure

```bash
terraform workspace select devel
terraform destroy -var-file="environments/devel.tfvars"

terraform workspace select stage
terraform destroy -var-file="environments/stage.tfvars"
```

(The S3 buckets have `force_destroy = true` on `aws_s3_bucket.site`, so Terraform empties them automatically before deleting.)
