# =======================================================
# 1. Provider 및 Backend 설정
# =======================================================

provider "aws" {
  region = "ap-northeast-2"
}

terraform {
  backend "s3" {
    bucket         = "chxtwo-git"
    key            = "personal-project/eks/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-state-lock"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

locals {
  project_name  = "stock-analysis-eks"
  vpc_cidr      = "10.0.0.0/16"
  public_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
  azs           = ["ap-northeast-2a", "ap-northeast-2c"]
}

# =======================================================
# 2. Networking (VPC, Subnet, IGW, NAT Gateway)
# =======================================================

resource "aws_vpc" "main" {
  cidr_block = local.vpc_cidr
  enable_dns_hostnames = true
  tags = {
    Name = "${local.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${local.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count             = length(local.public_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.public_cidrs[count.index]
  availability_zone = local.azs[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name                               = "${local.project_name}-public-${local.azs[count.index]}"
    "kubernetes.io/role/elb"           = "1"
  }
}

resource "aws_subnet" "private" {
  count             = length(local.private_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags = {
    Name                               = "${local.project_name}-private-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb"  = "1"
    "kubernetes.io/cluster/${local.project_name}" = "owned"
  }
}

resource "aws_eip" "nat" {
  count = length(aws_subnet.public)
  domain = "vpc"
}

resource "aws_nat_gateway" "gw" {
  count         = length(aws_subnet.public)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags = {
    Name = "${local.project_name}-nat-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table" "private" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.gw[count.index].id
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# =======================================================
# 3. EKS Cluster & IAM Roles
# =======================================================

resource "aws_iam_role" "eks_master" {
  name = "${local.project_name}-eks-master-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_master_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_master.name
}
resource "aws_iam_role_policy_attachment" "eks_vpc_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_master.name
}

resource "aws_iam_role" "eks_node" {
  name = "${local.project_name}-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node.name
}
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node.name
}
resource "aws_iam_role_policy_attachment" "eks_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node.name
}

resource "aws_eks_cluster" "main" {
  name     = local.project_name
  role_arn = aws_iam_role.eks_master.arn
  version  = "1.34"
  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = []
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }
  depends_on = [
    aws_iam_role_policy_attachment.eks_master_policy,
    aws_iam_role_policy_attachment.eks_vpc_cni_policy,
  ]
}

resource "aws_eks_node_group" "private" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.project_name}-ng-private"
  subnet_ids      = aws_subnet.private[*].id
  node_role_arn   = aws_iam_role.eks_node.arn
  instance_types  = ["t3.small"] 
  disk_size       = 20

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name = "${local.project_name}-ng"
    "k8s.io/cluster-autoscaler/enabled"        = "true"
    "k8s.io/cluster-autoscaler/${local.project_name}" = "owned"
  }
  depends_on = [
    aws_iam_role_policy_attachment.eks_node_policy,
  ]
}

# =======================================================
# 4. Cluster Autoscaler Setup (IRSA & Kubernetes Deployment)
# =======================================================

data "aws_eks_cluster" "main_data" {
  name = aws_eks_cluster.main.name
}

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "ca" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.main_data.identity[0].oidc[0].issuer
}

data "aws_iam_policy_document" "ca_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.ca.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${data.aws_eks_cluster.main_data.identity[0].oidc[0].issuer}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }
    condition {
      test     = "StringEquals"
      variable = "${data.aws_eks_cluster.main_data.identity[0].oidc[0].issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ca" {
  name               = "${local.project_name}-ca-role"
  assume_role_policy = data.aws_iam_policy_document.ca_assume_role.json
}

resource "aws_iam_policy" "ca" {
  name        = "${local.project_name}-ca-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions",
      ],
      Effect = "Allow",
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ca" {
  policy_arn = aws_iam_policy.ca.arn
  role       = aws_iam_role.ca.name
}

data "aws_eks_cluster_auth" "main_auth" {
  name = aws_eks_cluster.main.name
}

provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main_auth.token
}

resource "kubernetes_service_account" "ca" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.ca.arn
    }
  }
}

resource "kubernetes_cluster_role" "ca_role" {
  metadata { name = "cluster-autoscaler" }
  rule {
    api_groups = [""]
    resources = ["nodes", "pods", "services", "replicationcontrollers", "endpoints", "events", "persistentvolumeclaims", "persistentvolumes"]
    verbs = ["*"]
  }
  rule {
    api_groups = ["apps"]
    resources = ["daemonsets", "deployments", "replicasets", "statefulsets"]
    verbs = ["*"]
  }
  rule {
    api_groups = ["autoscaling"]
    resources = ["horizontalpodautoscalers"]
    verbs = ["*"]
  }
  rule {
    api_groups = ["policy"]
    resources = ["poddisruptionbudgets"]
    verbs = ["*"]
  }
}

resource "kubernetes_cluster_role_binding" "ca_binding" {
  metadata { name = "cluster-autoscaler" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.ca_role.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.ca.metadata[0].name
    namespace = kubernetes_service_account.ca.metadata[0].namespace
  }
}

resource "kubernetes_deployment" "ca" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    labels    = { app = "cluster-autoscaler" }
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "cluster-autoscaler" } }
    template {
      metadata { labels = { app = "cluster-autoscaler" } }
      spec {
        service_account_name = kubernetes_service_account.ca.metadata[0].name
        container {
          name  = "cluster-autoscaler"
          # EKS 1.34 호환 버전 사용
          image = "registry.k8s.io/autoscaling/cluster-autoscaler:v1.30.0" 

          command = [
            "./cluster-autoscaler",
            "--v=4",
            "--stderrthreshold=info",
            "--cloud-provider=aws",
            "--skip-nodes-with-local-storage=false",
            "--expander=least-waste",
            "--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/${local.project_name}",
            "--balance-similar-node-groups",
          ]
          env { 
  name  = "AWS_REGION" 
  value = "ap-northeast-2" 
}
        }
      }
    }
  }
  depends_on = [
    aws_eks_node_group.private,
  ]
}

# =======================================================
# 5. ECR 및 Outputs
# =======================================================

resource "aws_ecr_repository" "app" {
  name                 = "${local.project_name}-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

output "ecr_repository_url" {
  description = "ECR repository URL for CI/CD pipeline"
  value       = aws_ecr_repository.app.repository_url
}

