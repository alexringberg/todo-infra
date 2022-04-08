terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

# data "terraform_remote_state" "network" {
#   backend = "s3"
#   config = {
#     bucket = "terraform-state-management-ringberg"
#     key    = "network/terraform.tfstate"
#     region = "us-east-1"
#   }
# }

resource "aws_s3_bucket" "terraform-state" {
  bucket = "terraform-state-management-ringberg"
  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

}

resource "aws_instance" "todo-app-server" {
  ami                         = "ami-0c02fb55956c7d316"
  instance_type               = "t2.micro"
  key_name                    = "TodoAppServerKey"
  associate_public_ip_address = true
  security_groups             = [aws_security_group.todo-app-server-sg.id]
  subnet_id                   = aws_subnet.main-subnet.id
  user_data                   = <<-EOF
    #!/bin/bash
    set -ex
    sudo yum update -y
    sudo amazon-linux-extras install docker -y
    sudo service docker start
    sudo usermod -a -G docker ec2-user
    sudo curl -L https://github.com/docker/compose/releases/download/1.25.4/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    sudo docker run -d -p 8080:8080 ringberg/todo-app-spring:latest
  EOF

  tags = {
    "Name" = "TodoAppServer"
  }
}

resource "aws_security_group" "todo-app-server-sg" {
  name        = "todo-app-server-sg"
  description = "Allow ssh for inbound traffic"
  vpc_id      = aws_vpc.main-vpc.id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 8080
    protocol    = "tcp"
    to_port     = 8080
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 8080
    protocol    = "tcp"
    to_port     = 8080
  }
}

resource "aws_vpc" "main-vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "Main VPC"
  }
}

resource "aws_subnet" "main-subnet" {
  cidr_block        = cidrsubnet(aws_vpc.main-vpc.cidr_block, 3, 1)
  vpc_id            = aws_vpc.main-vpc.id
  availability_zone = "us-east-1a"
}

resource "aws_eip" "todo-app-server-ip" {
  instance = aws_instance.todo-app-server.id
  vpc      = true
}

resource "aws_internet_gateway" "main-gateway" {
  vpc_id = aws_vpc.main-vpc.id
  tags = {
    Name = "Main Gateway"
  }
}

resource "aws_route_table" "main-route-table" {
  vpc_id = aws_vpc.main-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main-gateway.id
  }

  tags = {
    Name = "Main Route Table"
  }
}

resource "aws_route_table_association" "main-route-table-association" {
  subnet_id      = aws_subnet.main-subnet.id
  route_table_id = aws_route_table.main-route-table.id
}


