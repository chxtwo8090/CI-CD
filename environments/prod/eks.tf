# eks.tf

# ---------------------------------------------
# 1. EKS 클러스터 및 Node Group (t3.small)
# ---------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 18.0"

  cluster_name    = "chan-gyu-stock-eks"
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets 

  # ⬇️ [최종 수정]: EKS 제어 영역 KMS 암호화 비활성화
  create_kms_key = false 

  eks_managed_node_groups = {
    cost_efficient_nodes = {
      min_size       = 1
      max_size       = 2
      desired_size   = 2
      instance_types = ["t3.small"] 
      ami_type       = "AL2023_x86_64_STANDARD"
      disk_size      = 20
    }
  }
}

# ---------------------------------------------
# 2. GitHubActions Role에게 KMS 키 접근 권한을 부여하는 정책 연결 해제 및 DynamoDB 권한 유지
# ---------------------------------------------
# ⚠️ 주의: aws_iam_policy.kms_key_access_policy 리소스와
#         aws_iam_role_policy_attachment.github_actions_kms_attach 리소스는 
#         더 이상 필요 없으므로 eks.tf 파일에서 제거해야 합니다.

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

resource "aws_iam_role_policy_attachment" "dynamodb_sa_attach" {
  role       = module.eks.eks_managed_node_groups["cost_efficient_nodes"].iam_role_name 
  policy_arn = aws_iam_policy.dynamodb_access_policy.arn
}