data "aws_caller_identity" "current" {}

resource "aws_iam_role" "karpenter_controller" {
  name = "${var.cluster_name}-karpenter"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(var.cluster_endpoint, "https://", "")}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
    }]
  })
}