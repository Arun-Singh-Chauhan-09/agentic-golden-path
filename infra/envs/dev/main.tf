terraform {
  required_version = ">= 1.10" # S3-native locking (use_lockfile) needs 1.10+
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = local.tags
  }
}

locals {
  name = "agentic-gp-${var.environment}"
  tags = {
    Project     = "agentic-golden-path"
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = "platform"
  }
}

module "network" {
  source   = "../../modules/network"
  name     = local.name
  az_count = 2
  tags     = local.tags
}

module "service" {
  source             = "../../modules/ecs-service"
  name               = local.name
  region             = var.region
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  image_tag          = var.image_tag
  desired_count      = 2
  mock_llm           = true # dev stays mocked; no Bedrock spend
  force_delete_ecr   = true
  tags               = local.tags
}

module "data" {
  source                = "../../modules/data"
  name                  = local.name
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  app_security_group_id = module.service.service_security_group_id
  deletion_protection   = false
  multi_az              = false
  tags                  = local.tags
}

module "observability" {
  source               = "../../modules/observability"
  name                 = local.name
  alb_arn_suffix       = module.service.alb_arn_suffix
  error_rate_threshold = 0.005 # 99.5% availability SLO
  latency_p95_seconds  = 1.0
  tags                 = local.tags
}
