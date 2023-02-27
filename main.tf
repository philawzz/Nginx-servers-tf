
# Provider Block
provider "aws" {
  # Configuration options
}


# VPC Block
resource "aws_vpc" "nginx-vpc" {
  cidr_block           = "10.28.0.0/16"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
  instance_tenancy     = "default"

  tags = {
    Name = "alb-vpc-Nginx"
  }
}


# Local Variables referenced for deploying resources below
locals {
  subnets = { "alb-subnet-a" = { availability_zone = "eu-west-2a", cidr_block = "10.28.0.0/24", server = "nginx-server-a" },
  "alb-subnet-b" = { availability_zone = "eu-west-2b", cidr_block = "10.28.5.0/24", server = "nginx-server-b" } }

}


# Subnets block - Create two subnets in the nginx VPC
resource "aws_subnet" "alb-subnets" {
  vpc_id                  = aws_vpc.nginx-vpc.id         // Referencing to the id of the VPC from the vpc resource block
  cidr_block              = each.value.cidr_block        // Referencing to the local variable
  map_public_ip_on_launch = "true"                       // Makes both subnets public subnets
  availability_zone       = each.value.availability_zone // Referencing to the local variable
  for_each                = local.subnets

  tags = {
    Name = each.key
  }
}


resource "aws_internet_gateway" "alb-igw" {
  vpc_id = aws_vpc.nginx-vpc.id // Subnets uses this IGW to reach internet
}


resource "aws_route_table" "alb-rt-main" {
  vpc_id = aws_vpc.nginx-vpc.id
  route {
    cidr_block = "0.0.0.0/0" // Associated subnets can reach everywhere
    gateway_id = aws_internet_gateway.alb-igw.id
  }

  tags = {
    Name = "alb-public-rt"
  }
}


resource "aws_route_table_association" "alb-rt-subnets-association" {
  subnet_id      = aws_subnet.alb-subnets[each.key].id
  route_table_id = aws_route_table.alb-rt-main.id
  for_each       = local.subnets

}


# Security group allows HTTP, SSH
resource "aws_security_group" "ec2-alb-acess" {
  vpc_id = aws_vpc.nginx-vpc.id


  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // Ideally best to use your ALB's IP.
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // To allow EC2 instance connect to test Nginx status.
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nginx-server-alb-sg"
  }
}


# Deploys two instances with nginx bootstrapped
resource "aws_instance" "nginx-servers" {
  subnet_id     = aws_subnet.alb-subnets[each.key].id
  ami           = "ami-09ee0944866c73f62"
  instance_type = "t2.micro"
  key_name      = "London02"
  for_each      = local.subnets


  user_data = <<-EOF
                #!/bin/bash
                sudo yum update -y
                sudo amazon-linux-extras install nginx1 -y
                sudo systemctl enable nginx
                sudo systemctl start nginx
                EOF

  tags = {
    Name = each.value.server
  }

  # Security Group
  vpc_security_group_ids = [aws_security_group.ec2-alb-acess.id]

}


# Outputs the public ips of both servers
output "nginx-servers" {
  description = "ID of nginx servers"
  value       = aws_instance.nginx-servers
}
