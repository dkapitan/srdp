# Uses the bundled terraform ruleset (no plugin download needed).
# To add Scaleway-specific linting later: add a `plugin "scaleway"` block and run
# `tflint --init` (requires network).
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Provider + Terraform versions are pinned centrally in the env roots
# (envs/*, deploy/bootstrap); child modules inherit them. These two rules would
# otherwise demand the version pins be duplicated into every module.
rule "terraform_required_version" {
  enabled = false
}
rule "terraform_required_providers" {
  enabled = false
}
