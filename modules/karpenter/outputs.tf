output "controller_role_arn" {
  value = aws_iam_role.karpenter_controller.arn
}

output "node_role_name" {
  value = aws_iam_role.karpenter_node.name
}

output "node_role_arn" {
  value = aws_iam_role.karpenter_node.arn
}
