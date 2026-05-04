module "vpc" {
  source = "../modules/vpc"
}

module "eks" {
  source       = "../modules/eks"
  cluster_name = var.cluster_name
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.private_subnets
}

module "karpenter" {
  source          = "../modules/karpenter"
  cluster_name    = var.cluster_name
  cluster_endpoint = module.eks.endpoint
}