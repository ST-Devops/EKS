output "cluster_name" {
  value = module.eks.cluster_name
}

output "karpenter_controller_role_arn" {
  value = module.karpenter.controller_role_arn
}

output "karpenter_node_role_name" {
  value = module.karpenter.node_role_name
}
