variable "cluster_name" {}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL from the EKS cluster identity block."
  type        = string
}
