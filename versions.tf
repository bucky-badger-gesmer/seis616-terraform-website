terraform {
  required_version = ">= 1.2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Credentials come from the environment (AWS_PROFILE), not from code.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "seis616-terraform-website"
    }
  }
}
