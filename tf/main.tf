terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">=5.55"
    }
  }
}
provider "aws" {
  region  = var.region
  profile = "default"  # change in case you want to work with another AWS account profile
}

module "k8s-cluster" {
  source = "./modules/k8s-cluster"
  env    = var.env
  username = var.username
  region = var.region
  azs    = var.azs
  ami_id = var.ami_id
  key_pair_name = var.key_pair_name
}