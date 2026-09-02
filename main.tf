terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# 1. Fetch latest official Ubuntu 22.04 AMI dynamically
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

# 2. Firewall Rule (Security Group)
resource "aws_security_group" "starrocks_sg" {
  name_prefix = "starrocks-sg-" # Generates a unique name dynamically
  description = "Allow MySQL access to StarRocks"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9030
    to_port     = 9030
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. AWS EC2 Server
resource "aws_instance" "starrocks_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.starrocks_sg.id] # Reference by ID instead of name

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker

              # Run all-in-one StarRocks container
              docker run -p 9030:9030 -p 8030:8030 -p 8040:8040 -itd --name starrocks starrocks/all-in-1-ubuntu
              EOF

  tags = {
    Name = "StarRocks-DataTeam-Test"
  }
}

# 4. Connection Output
output "data_team_connection_string" {
  value       = "mysql -h ${aws_instance.starrocks_server.public_ip} -P 9030 -u root"
  description = "Share this connection command with the Data Analysis team"
}