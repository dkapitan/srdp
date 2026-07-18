# State backend bootstrap

Creates the Terraform **state backend** — a Scaleway Object Storage bucket named
`<prefix>-tfstate-<env>` — that `envs/<env>` expect via Terraform's S3 backend.

By default the Justfile points **every** env at a single shared bucket
(`TFSTATE_BUCKET`, default `<prefix>-tfstate-hub`) and isolates envs by object key
(`<env>.tfstate`), so you only need to bootstrap `hub` once. To get one bucket per
Project instead, set `TFSTATE_BUCKET` per env and bootstrap each. Run **before**
any `terraform init` in an env.

This config uses **local state** by design: it builds the remote backend, so it
can't yet store its own state there.

## Run (via the Justfile — recommended)

```bash
just bootstrap-state hub
just bootstrap-state dev
just bootstrap-state stage
just bootstrap-state prod
```

## Run (directly)

```bash
cd deploy/bootstrap
terraform init
terraform apply -state=terraform-dev.tfstate \
  -var prefix=acme -var env=dev \
  -var region=nl-ams \
  -var project_id=<dev-project-id>
# repeat for hub + each remaining env with its Project id + -state=terraform-<env>.tfstate
```

> The per-env `-state=` is important: a shared state file makes each run replace
> the previous Project's bucket (single bucket resource). One state file per env.

## S3 backend wiring

`envs/<env>` declare an empty `backend "s3" {}`; the Justfile injects:

```
bucket                      = <prefix>-tfstate-<env>
key                         = <env>.tfstate
region                      = nl-ams
endpoints.s3                = https://s3.nl-ams.scw.cloud
access_key / secret_key     = SCW_ACCESS_KEY / SCW_SECRET_KEY
skip_credentials_validation = true
skip_region_validation      = true
skip_requesting_account_id  = true
```

Keep `deploy/bootstrap/terraform-*.tfstate` safe — they only track these
foundational buckets and rarely change.
