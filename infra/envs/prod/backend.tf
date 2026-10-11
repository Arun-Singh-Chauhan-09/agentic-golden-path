terraform {
  backend "s3" {
    bucket       = "REPLACE-ME-tfstate-bucket"
    key          = "agentic-golden-path/prod/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
