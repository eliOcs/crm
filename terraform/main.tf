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

# ECR Repository for Rails app
resource "aws_ecr_repository" "crm" {
  name                 = "crm"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}

# ECR Repository for Postfix mail server
resource "aws_ecr_repository" "crm_postfix" {
  name                 = "crm-postfix"
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

  # SMTP (inbound email)
  ingress {
    from_port   = 25
    to_port     = 25
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SMTP inbound email"
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
    delete_on_termination = false # Keep data if instance is terminated
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

# =============================================================================
# Route 53 DNS for Email
# =============================================================================

data "aws_route53_zone" "main" {
  name = var.domain_name
}

# MX record for inbox subdomain - receives forwarded emails
resource "aws_route53_record" "inbox_mx" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "inbox.${var.domain_name}"
  type    = "MX"
  ttl     = 300
  records = ["10 ${var.domain_name}"]
}

# SPF for inbox subdomain - declares we don't send from this subdomain
resource "aws_route53_record" "inbox_spf" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "inbox.${var.domain_name}"
  type    = "TXT"
  ttl     = 300
  records = ["v=spf1 -all"]
}

# SPF for main domain - allows the server to send email
resource "aws_route53_record" "main_spf" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 300
  records = [
    "v=spf1 a mx -all",
    "google-site-verification=Aa9EFFs_vyO5B-lNNg_UPc--O4tJKXhqooUpuRYk0_I"
  ]
}

# MX for main domain (optional - in case someone emails user@mercuriocrm.es)
resource "aws_route53_record" "main_mx" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "MX"
  ttl     = 300
  records = ["10 ${var.domain_name}"]
}

# A record for mail server hostname (required for reverse DNS)
resource "aws_route53_record" "mail_a" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "mail.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.crm.public_ip]
}

# Reverse DNS for Elastic IP (PTR record: IP -> mail.mercuriocrm.es)
# Required for proper email server identification
resource "aws_eip_domain_name" "crm_rdns" {
  allocation_id = aws_eip.crm.allocation_id
  domain_name   = "mail.${var.domain_name}"
}

# DMARC policy - tells receivers to reject unauthenticated emails
resource "aws_route53_record" "dmarc" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 300
  records = ["v=DMARC1; p=reject; rua=mailto:dmarc@${var.domain_name}; adkim=s; aspf=s"]
}

# DKIM public key for email signing verification
# Key generated by OpenDKIM on mail server, selector: mail
resource "aws_route53_record" "dkim" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "mail._domainkey.${var.domain_name}"
  type    = "TXT"
  ttl     = 300
  # Long key split into 255-byte chunks per DNS TXT record spec
  # Format matches AWS CLI output with space-separated quoted strings
  records = [
    "v=DKIM1; k=rsa; p=\" \"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1/8jdA4h/Ign8/JN4SiaY88fXglEjM5a/MI3fRUgSLMlooa/yaTV9O96JefN1LXKOnP0mxPqIppMBd2sYOt293WHdoUpDbWRyVYvjC/+oBCIOj7tRBsGbOAj3M598s/Q0vZVtyuFj9+zk3AxEDjtx8qk9aOGLIAcii42h/44WWP5\" \"Z/KcfijWxWYG8NexNm4QG45F0QVidDt01pqigWTI5F/tOIs6+oj0do9al272yK1e1tubIc367SBO4asgroQzamMBGl3duAXuzBnTm0prtql4au1e6An6nYvDBMj25KuI6sFnBjZxXltY1B0zYsq6LVwCO31EGkT/XgdF+Qjt+wIDAQAB"
  ]
}

# =============================================================================
# BIMI (Brand Indicators for Message Identification)
# =============================================================================

# BIMI record - points to brand logo for email clients
# Note: Without VMC, logo display depends on email provider (Yahoo/AOL show, Gmail doesn't)
resource "aws_route53_record" "bimi" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "default._bimi.${var.domain_name}"
  type    = "TXT"
  ttl     = 300
  records = ["v=BIMI1; l=https://${var.domain_name}/logo.svg"]
}
