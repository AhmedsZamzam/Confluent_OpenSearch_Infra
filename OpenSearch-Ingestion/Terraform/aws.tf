data "aws_region" "current" {}
data "aws_caller_identity" "current" {}


resource "random_id" "vpc_display_id" {
    byte_length = 4
}
# ------------------------------------------------------
# VPC
# ------------------------------------------------------
resource "aws_vpc" "main" { 
    cidr_block = var.vpc_cidr
    enable_dns_hostnames = true
    tags = {
        Name = "${var.prefix}-${random_id.vpc_display_id.hex}"
    }
}

# ------------------------------------------------------
# Public SUBNETS
# ------------------------------------------------------

resource "aws_subnet" "public_subnets" {
    count = 3
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.${count.index+1}.0/24"
    map_public_ip_on_launch = true
    tags = {
        Name = "${var.prefix}-public-${count.index}-${random_id.vpc_display_id.hex}"
    }
}

# ------------------------------------------------------
# Private SUBNETS
# ------------------------------------------------------

resource "aws_subnet" "private_subnets" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 10}.0/24"
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false
  tags = {
    Name = "${var.prefix}-private-${count.index}-${random_id.vpc_display_id.hex}"
  }
}

# ------------------------------------------------------
# IGW
# ------------------------------------------------------
resource "aws_internet_gateway" "igw" { 
    vpc_id = aws_vpc.main.id
    tags = {
        Name = "${var.prefix}-${random_id.vpc_display_id.hex}"
    }
}

# ------------------------------------------------------
# EIP
# ------------------------------------------------------

resource "aws_eip" "eip" {
  vpc      = true
}

# ------------------------------------------------------
# NAT
# ------------------------------------------------------

resource "aws_nat_gateway" "natgw" {
  allocation_id = aws_eip.eip.id
  subnet_id = aws_subnet.public_subnets[1].id
  tags = {
    Name = "${var.prefix}-${random_id.vpc_display_id.hex}"
  }
}

# ------------------------------------------------------
# ROUTE TABLE
# ------------------------------------------------------
resource "aws_route_table" "public_route_table" {
    vpc_id = aws_vpc.main.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
    tags = {
        Name = "${var.prefix}-public-${random_id.vpc_display_id.hex}"
    }
}

resource "aws_route_table" "private_route_table" {
    vpc_id = aws_vpc.main.id
    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.natgw.id
    }
    tags = {
        Name = "${var.prefix}-private-${random_id.vpc_display_id.hex}"
    }
}

resource "aws_route_table_association" "pub_subnet_associations" {
    count = 3
    subnet_id = aws_subnet.public_subnets[count.index].id
    route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "pri_subnet_associations" {
    count = 3
    subnet_id = aws_subnet.private_subnets[count.index].id
    route_table_id = aws_route_table.private_route_table.id
}

# ------------------------------------------------------
# SG
# ------------------------------------------------------

# Inbound rule for port 443 from the main security group
resource "aws_security_group_rule" "self_ingress_443" {
  type            = "ingress"
  from_port       = 443
  to_port         = 443
  protocol        = "tcp"
  security_group_id = aws_security_group.sg.id
  source_security_group_id = aws_security_group.sg.id
}

resource "aws_security_group" "sg" {
  name        = "${var.prefix}-${random_id.vpc_display_id.hex}"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [aws_security_group.windows_sg.id]
  }

  ingress {
    from_port = 9092
    to_port = 9092
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}

# Security Group for Windows EC2 Instance
resource "aws_security_group" "windows_sg" {
  name        = "${var.prefix}-windows-sg-${random_id.vpc_display_id.hex}"
  description = "Allow RDP traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}-windows-sg-${random_id.vpc_display_id.hex}"
  }
}

# ------------------------------------------------------
# Secrets Manager
# ------------------------------------------------------

# Creating a AWS Secret for Confluent User 
resource "aws_secretsmanager_secret" "service_user" {
  name        = "${var.prefix}-confluent-secret-${random_id.vpc_display_id.hex}"
  description = "Service Account Username for the API"
}

resource "aws_secretsmanager_secret_version" "service_user" {
  secret_id     = aws_secretsmanager_secret.service_user.id
  secret_string = jsonencode({"username": "${confluent_api_key.app-manager-kafka-api-key.id}", "password": "${confluent_api_key.app-manager-kafka-api-key.secret}"})
}

# ------------------------------------------------------
# IAM Roles
# ------------------------------------------------------

# For IOT Core

resource "aws_iam_role_policy" "secrets_policy" {
  name = "${var.prefix}-secrets_manager_policy-${random_id.vpc_display_id.hex}"
  role = aws_iam_role.osi_role.id
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:*",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}




resource "aws_iam_role_policy" "eni_policy" {
  name = "${var.prefix}-eni-policy-${random_id.vpc_display_id.hex}"
  role = aws_iam_role.osi_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AttachNetworkInterface",
          "ec2:CreateNetworkInterface",
          "ec2:CreateNetworkInterfacePermission",
          "ec2:DeleteNetworkInterface",
          "ec2:DeleteNetworkInterfacePermission",
          "ec2:DetachNetworkInterface",
          "ec2:DescribeNetworkInterfaces"
        ]
        Resource = [
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:network-interface/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:subnet/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:security-group/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:Describe*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:*:*:network-interface/*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/OSISManaged" = "true"
          }
        }
      }
    ]
  })
}


resource "aws_iam_role_policy" "opensearch_access_policy" {
  name = "${var.prefix}-opensearch_access_policy-${random_id.vpc_display_id.hex}"
  role = aws_iam_role.osi_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "es:DescribeDomain"
        Resource = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/*"
      },
      {
        Effect = "Allow"
        Action = "es:ESHttp*"
        Resource = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.prefix}-opensearch/*"
      }
    ]
  })
}


resource "aws_iam_role" "osi_role" {
  name = "${var.prefix}-role-${random_id.vpc_display_id.hex}"
  managed_policy_arns = [
  "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"]  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "osis-pipelines.amazonaws.com"
        }
      },
    ]
  })
}

# ------------------------------------------------------
# OpenSearch Domain
# ------------------------------------------------------



resource "aws_opensearch_domain" "OpenSearch" {
  domain_name = "${var.prefix}-opensearch"

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = "es:*"
        Resource = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.prefix}-opensearch/*"
      }
    ]
  })


  cluster_config {
    instance_type = "t3.small.search"
    instance_count = 3
    zone_awareness_enabled = true
    zone_awareness_config {
      availability_zone_count = 3
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
    volume_type = "gp2"
  }

  node_to_node_encryption {
    enabled = true
  }

  encrypt_at_rest {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  vpc_options {
    subnet_ids = [for s in aws_subnet.private_subnets : s.id]
    security_group_ids = [aws_security_group.sg.id]
  }

  advanced_security_options {
    enabled = true
    internal_user_database_enabled = true

    master_user_options {
      master_user_name = var.opensearch_master_username
      master_user_password = var.opensearch_master_password
    }
  }

  tags = {
    Name = "${var.prefix}-opensearch-${random_id.vpc_display_id.hex}"
  }
}

# ------------------------------------------------------
# Windows EC2 Instance
# ------------------------------------------------------

data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base-*"]
  }
}

resource "aws_instance" "windows_instance" {
  ami                    = data.aws_ami.windows.image_id
  instance_type          = "t3.small"
  key_name               = "osi-zamzam" # Replace with your key pair name
  vpc_security_group_ids = [aws_security_group.windows_sg.id]
  subnet_id              = aws_subnet.public_subnets[0].id # Associate with the first public subnet
  root_block_device {
    volume_size = 30 # Adjust the volume size as needed
  }
  tags = {
    Name = "${var.prefix}-windows-instance-${random_id.vpc_display_id.hex}"
  }
}




# ------------------------------------------------------
# VPC Endpoint
# ------------------------------------------------------


resource "aws_vpc_endpoint" "privatelink" {
  vpc_id            = aws_vpc.main.id
  service_name      = confluent_private_link_attachment.pla.aws[0].vpc_endpoint_service_name
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.sg.id,
  ]

  subnet_ids = [for subnet in aws_subnet.private_subnets : subnet.id]

  private_dns_enabled = false

  tags = {
    Name = "${var.prefix}-confluent-private-link-endpoint-${random_id.vpc_display_id.hex}"
  }
}



# # ------------------------------------------------------
# VPC Endpoint
# ------------------------------------------------------


resource "aws_route53_zone" "privatelink" {
  name = confluent_private_link_attachment.pla.dns_domain

  vpc {
    vpc_id = aws_vpc.main.id
  }
}


resource "aws_route53_record" "privatelink" {
  zone_id = aws_route53_zone.privatelink.zone_id
  name = "*.${aws_route53_zone.privatelink.name}"
  type = "CNAME"
  ttl  = "60"
  records = [
    aws_vpc_endpoint.privatelink.dns_entry[0]["dns_name"]
  ]
}



