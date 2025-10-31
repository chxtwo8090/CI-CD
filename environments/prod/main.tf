# main.tf

# ---------------------------------------------
# 1. Terraform Backend (State File) 설정
# ---------------------------------------------
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "chxtwo-git"                 
    key            = "terraform/eks-stock.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-state-lock"       
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

# ---------------------------------------------
# 2. VPC 및 Subnet 구성
# ---------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "stock-project-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-northeast-2a", "ap-northeast-2b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true 
  enable_dns_hostnames   = true
  enable_dns_support     = true
}

# ---------------------------------------------
# 3. 애플리케이션용 DynamoDB 테이블 및 ECR 레포지토리
# ---------------------------------------------

# (기존) 주식 데이터 테이블 (NaverStockData)
resource "aws_dynamodb_table" "app_data_table" {
  name             = "NaverStockData"
  billing_mode     = "PROVISIONED"
  read_capacity    = 5
  write_capacity   = 5

  hash_key         = "StockId"
  range_key        = "Timestamp"

   attribute { 
    name = "StockId"
    type = "S" 
  }
  attribute { 
    name = "Timestamp" 
    type = "S" 
   }
  
  tags = {
    Name = "NaverStockData"
  }
}

# ⬇️ [수정 완료]: 새로운 테이블 추가 및 구문 오류 해결

# (추가) 1-1. 사용자 관리 테이블 (회원가입/로그인)
resource "aws_dynamodb_table" "user_table" {
  name             = "CommunityUsers"
  billing_mode     = "PAY_PER_REQUEST" # 비용 효율을 위해 온디맨드 사용
  hash_key         = "UserId"
  
  # ⬇️ hash_key 및 GSI가 참조할 attribute들을 정의
  attribute { 
    name = "UserId"
    type = "S"
  }
  attribute { 
    name = "Username"
    type = "S"
  }

  # 사용자 이름 중복 확인을 위한 GSI (Global Secondary Index)
  global_secondary_index {
    name               = "UsernameIndex"
    hash_key           = "Username"
    projection_type    = "ALL"
    # PAY_PER_REQUEST 모드에서는 read/write capacity 지정 불필요
  }
  
  tags = { Name = "CommunityUsers" }
}

# (추가) 1-2. 게시글/댓글 테이블 (종목토론방)
resource "aws_dynamodb_table" "post_table" {
  name             = "DiscussionPosts"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "StockCode"    # 종목 코드로 파티션
  range_key        = "PostId"       # PostId는 고유 값 (UUID)
  
  # ⬇️ hash_key와 range_key가 참조할 attribute들을 정의
  attribute { 
    name = "StockCode"
    type = "S" 
     }
  attribute { 
    name = "PostId"
    type = "S"
  }

  tags = { Name = "DiscussionPosts" }
}

# ⬆️ [수정 완료]: 새로운 테이블 추가 및 구문 오류 해결

# ECR 레포지토리 (Docker 이미지 저장소)
resource "aws_ecr_repository" "frontend" { name = "stock-web-app" }
resource "aws_ecr_repository" "backend" { name = "stock-api" }
# (추가) LLM 챗봇을 위한 ECR 레포지토리
resource "aws_ecr_repository" "llm_chatbot" { name = "llm-chatbot-api" }
