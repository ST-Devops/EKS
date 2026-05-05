module "vpc" {
  source       = "../modules/vpc"
  cluster_name = var.cluster_name
}

module "eks" {
  source                 = "../modules/eks"
  cluster_name           = var.cluster_name
  subnet_ids             = module.vpc.private_subnets
  node_security_group_id = module.vpc.node_security_group_id
}

module "karpenter" {
  source                  = "../modules/karpenter"
  cluster_name            = var.cluster_name
  cluster_oidc_issuer_url = module.eks.oidc_issuer_url
}
