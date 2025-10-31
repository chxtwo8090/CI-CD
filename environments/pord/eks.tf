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

  eks_managed_node_groups = {
    cost_efficient_nodes = {
      min_size       = 1
      max_size       = 2
      desired_size   = 2
      instance_types = ["t3.small"] # ⚠️ 사용자 요청 반영
      ami_type       = "AL2023_X86_64_STANDARD"
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
  # EKS 모듈이 자동으로 생성한 ServiceAccount Role에 정책 연결 
  role       = module.eks.cluster_primary_role_name 
  policy_arn = aws_iam_policy.dynamodb_access_policy.arn
}