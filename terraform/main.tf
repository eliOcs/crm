terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# Use default VPC for simplicity
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ECR Repository
resource "aws_ecr_repository" "crm" {
  name                 = "crm"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}

# Security Group
resource "aws_security_group" "crm" {
  name        = "crm-sg"
  description = "CRM app security group"
  vpc_id      = data.aws_vpc.default.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access"
  }

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS access"
  }

  # Outbound (allow all)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "crm-sg"
  }
}

# SSH Key Pair
resource "aws_key_pair" "crm" {
  key_name   = "crm-key"
  public_key = file(var.ssh_public_key_path)
}

# Get latest Ubuntu 24.04 ARM64 AMI
data "aws_ami" "ubuntu_arm" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# EC2 Instance (Graviton)
resource "aws_instance" "crm" {
  ami                    = data.aws_ami.ubuntu_arm.id
  instance_type          = "t4g.small"
  key_name               = aws_key_pair.crm.key_name
  vpc_security_group_ids = [aws_security_group.crm.id]
  subnet_id              = data.aws_subnets.default.ids[0]

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = false  # Keep data if instance is terminated
    encrypted             = true
  }

  tags = {
    Name = "crm-server"
  }
}

# Elastic IP (static IP that persists across instance stop/start)
resource "aws_eip" "crm" {
  instance = aws_instance.crm.id
  domain   = "vpc"

  tags = {
    Name = "crm-ip"
  }
}
