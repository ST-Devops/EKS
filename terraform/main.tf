module "vpc" {
  source = "../modules/vpc"
}

module "eks" {
  source                      = "../modules/eks"
  cluster_name                = var.cluster_name
  vpc_id                      = module.vpc.vpc_id
  subnet_ids                  = module.vpc.private_subnets
  cluster_security_group_id   = module.vpc.cluster_security_group_id
  node_security_group_id      = module.vpc.node_security_group_id
}

module "karpenter" {
  source          = "../modules/karpenter"
  cluster_name    = var.cluster_name
  cluster_endpoint = module.eks.endpoint
}