terraform {
  required_version = ">= 1.5"

  cloud {
    organization = "st-learn-devops"

    workspaces {
      name = "eks-learning"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source = "hashicorp/helm"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "aws" {
  region = var.region
}