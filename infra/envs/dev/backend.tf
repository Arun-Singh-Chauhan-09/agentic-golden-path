terraform {
  backend "s3" {
    bucket       = "REPLACE-ME-tfstate-bucket"
    key          = "agentic-golden-path/dev/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true # S3-native state locking (TF >= 1.10); no DynamoDB needed
  }
}
