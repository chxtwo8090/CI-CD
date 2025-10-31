# iam.tf

# ---------------------------------------------
# 1. GitHub OIDC Provider 생성
# ---------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = ["a0d0cf50854c6532e8316c141724d2d4c0620f4c"]
}

# ---------------------------------------------
# 2. GitHub Actions가 Assume할 IAM Role 생성
# ---------------------------------------------
resource "aws_iam_role" "github_actions_role" {
  name = "GitHubActions-Terraform-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # ⚠️ 사용자 GitHub 이름으로 반드시 대체해야 합니다. 레포지토리는 'CI-CD'입니다.
          "token.actions.githubusercontent.com:sub" = "repo:chxtwo8090/CI-CD:ref:refs/heads/main" 
        }
      }
    }]
  })
}

# 3. Role에 Administrator 권한 부여
resource "aws_iam_role_policy_attachment" "admin_access" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.github_actions_role.name
}

# ---------------------------------------------
# 4. 출력: OIDC Role ARN (GitHub Secrets에 등록해야 함)
# ---------------------------------------------
output "github_actions_iam_role_arn" {
   value = aws_iam_role.github_actions_role.arn
}