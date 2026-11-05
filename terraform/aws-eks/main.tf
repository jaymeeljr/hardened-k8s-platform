data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# KMS: one customer-managed key for Kubernetes Secrets and all log groups
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "kms" {
  # In a KMS *key policy*, Resource "*" means "this key only" (AWS-documented
  # pattern); access is constrained by the principals and conditions below.
  # checkov:skip=CKV_AWS_111:Key policy; resource scope is the key itself
  # checkov:skip=CKV_AWS_356:Key policy; resource scope is the key itself
  # checkov:skip=CKV_AWS_109:Key policy; account root must administer its own key
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchLogsEncryption"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_kms_key" "platform" {
  description             = "${var.cluster_name}: EKS secrets and log encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "platform" {
  name          = "alias/${var.cluster_name}"
  target_key_id = aws_kms_key.platform.key_id
}

# ---------------------------------------------------------------------------
# Network: nodes live in private subnets only; flow logs for forensics
# ---------------------------------------------------------------------------
# Modules are pinned to the exact commit behind each release tag, so a moved
# or compromised tag cannot change what gets deployed (supply-chain hardening).
module "vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=b3abd6df2ecf052451a361ed55b8f06f8742a795" # v6.7.3

  name = var.cluster_name
  cidr = "10.0.0.0/16"
  azs  = var.availability_zones

  private_subnets = ["10.0.0.0/19", "10.0.32.0/19", "10.0.64.0/19"]
  public_subnets  = ["10.0.96.0/22", "10.0.100.0/22", "10.0.104.0/22"]

  enable_nat_gateway = true
  single_nat_gateway = true

  # Lock down the default security group so nothing can use it by accident.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_cloudwatch_log_group_retention_in_days = var.log_retention_days
  flow_log_cloudwatch_log_group_kms_key_id        = aws_kms_key.platform.arn

  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}

# ---------------------------------------------------------------------------
# EKS cluster
# ---------------------------------------------------------------------------
module "eks" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=5858b0f9652f6c7bdc8f6639a4885ce9221189ef" # v21.28.1

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # API endpoint: private inside the VPC, public only for allow-listed CIDRs.
  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.admin_cidrs

  # Access entries (API mode) instead of the legacy aws-auth ConfigMap.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  # Envelope-encrypt Kubernetes Secrets with our own KMS key.
  create_kms_key = false
  encryption_config = {
    provider_key_arn = aws_kms_key.platform.arn
    resources        = ["secrets"]
  }

  # Full control-plane audit trail, encrypted and retained for a year.
  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = var.log_retention_days
  cloudwatch_log_group_kms_key_id        = aws_kms_key.platform.arn

  # IAM Roles for Service Accounts: per-pod AWS permissions, no node-wide keys.
  enable_irsa = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
      # Native NetworkPolicy enforcement, so the policies in k8s/ apply on EKS too.
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    eks-pod-identity-agent = { before_compute = true }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2

      # IMDSv2 only, one hop: pods cannot steal the node's IAM credentials.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }

      block_device_mappings = {
        root = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            encrypted             = true
            kms_key_id            = aws_kms_key.platform.arn
            delete_on_termination = true
          }
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# GuardDuty: EKS audit-log analysis and runtime threat detection
# ---------------------------------------------------------------------------
resource "aws_guardduty_detector" "this" {
  # checkov:skip=CKV2_AWS_3:Single-account demo; org-wide GuardDuty is managed from the security account
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

resource "aws_guardduty_detector_feature" "eks_audit_logs" {
  detector_id = aws_guardduty_detector.this.id
  name        = "EKS_AUDIT_LOGS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "runtime_monitoring" {
  detector_id = aws_guardduty_detector.this.id
  name        = "RUNTIME_MONITORING"
  status      = "ENABLED"

  additional_configuration {
    name   = "EKS_ADDON_MANAGEMENT"
    status = "ENABLED"
  }
}
