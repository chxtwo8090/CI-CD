# eks.tf

# ---------------------------------------------
# 1. EKS 클러스터 및 Node Group (t3.small)
# ---------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.16"

  cluster_name    = "chan-gyu-stock-eks"
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # EKS 노드는 프라이빗 서브넷에 위치

  # ⬇️ [수정]: KMS 키 관리자 ARN 추가 (권한 오류 해결)
  create_kms_key = true 
  kms_key_administrator_arns = [
    "arn:aws:iam::798874239435:role/GitHubActions-Terraform-Role"
  ]

  eks_managed_node_groups = {
    cost_efficient_nodes = {
      min_size       = 1
      max_size       = 2
      desired_size   = 2
      instance_types = ["t3.small"] 
      ami_type       = "AL2023_x86_64_STANDARD" # ⬅️ 이전 오타 수정 반영됨
      disk_size      = 20
    }
  }
}

# ---------------------------------------------
# 2. EKS Pod의 DynamoDB 접근 권한 (IRSA)
# ---------------------------------------------

# DynamoDB 읽기/쓰기 정책 정의
resource "aws_iam_policy" "dynamodb_access_policy" {
  name = "EKS-DynamoDB-Access-Policy-for-App"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query",
        "dynamodb:UpdateItem", "dynamodb:DeleteItem"
      ]
      Resource = [aws_dynamodb_table.app_data_table.arn]
    }]
  })
}

# EKS Service Account Role에 DynamoDB 정책 연결
 resource "aws_iam_role_policy_attachment" "dynamodb_sa_attach" {
  role       = module.eks.eks_managed_node_groups["cost_efficient_nodes"].iam_role_name 
  policy_arn = aws_iam_policy.dynamodb_access_policy.arn
}