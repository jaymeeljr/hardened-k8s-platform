variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-central-1"
}

variable "availability_zones" {
  description = "Explicit AZs, so the subnet layout never changes when AWS adds a zone."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "hardened-platform"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.34"
}

variable "admin_cidrs" {
  description = "CIDR ranges allowed to reach the public API endpoint (e.g. office or VPN egress IPs)."
  type        = list(string)

  validation {
    condition     = length(var.admin_cidrs) > 0 && !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "admin_cidrs must list specific ranges; exposing the API endpoint to 0.0.0.0/0 is not allowed."
  }
}

variable "log_retention_days" {
  description = "Retention for control-plane and VPC flow logs (365 days meets common audit requirements)."
  type        = number
  default     = 365
}
