module "vpc" {
  source = "../modules/vpc"
}

module "eks" {
  source                 = "../modules/eks"
  cluster_name           = var.cluster_name
  subnet_ids             = module.vpc.private_subnets
  node_security_group_id = module.vpc.node_security_group_id
}

module "karpenter" {
  source           = "../modules/karpenter"
  cluster_name     = var.cluster_name
  cluster_endpoint = module.eks.endpoint
}