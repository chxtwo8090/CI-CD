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
    bucket         = "chxtwo-git"                 # ⚠️ 사용자 S3 버킷 이름
    key            = "terraform/eks-stock.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-state-lock"       # ⚠️ DynamoDB Lock 테이블 이름 (선행 작업 필요)
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
  single_nat_gateway     = true # 비용 절감을 위해 NAT Gateway 1개만 사용
  enable_dns_hostnames   = true
  enable_dns_support     = true
}

# ---------------------------------------------
# 3. 애플리케이션용 DynamoDB 테이블 및 ECR 레포지토리
# ---------------------------------------------

# 애플리케이션 데이터 테이블 (NaverStockData)
resource "aws_dynamodb_table" "app_data_table" {
  name             = "NaverStockData"
  billing_mode     = "PROVISIONED"
  read_capacity    = 5
  write_capacity   = 5

  hash_key         = "StockId"
  range_key        = "Timestamp"

  attribute { name = "StockId", type = "S" }
  attribute { name = "Timestamp", type = "S" }
  
  tags = {
    Name = "NaverStockData"
  }
}

# ECR 레포지토리 (Docker 이미지 저장소)
resource "aws_ecr_repository" "frontend" { name = "stock-web-app" }
resource "aws_ecr_repository" "backend" { name = "stock-api" }