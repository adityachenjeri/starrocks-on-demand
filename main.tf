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

  owners = ["099720109477"] # Canonical
}

# 2. Security Group
resource "aws_security_group" "starrocks_sg" {
  name_prefix = "starrocks-sg-"
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

# 3. EC2 Instance
resource "aws_instance" "starrocks_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  # Fix for 'No space left on device': Expand EBS Root Disk to 20GB
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  vpc_security_group_ids = [aws_security_group.starrocks_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io mysql-client-core-8.0

              # 4GB Swap Space
              fallocate -l 4G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              systemctl start docker
              systemctl enable docker

              # Launch StarRocks FE
              docker run -d \
                --name starrocks-fe \
                --net=host \
                --restart always \
                -e FE_SERVERS="fe1:127.0.0.1:9010" \
                -e FE_ID=1 \
                -e JAVA_OPTS="-Xmx768m -Xms768m" \
                starrocks/fe-ubuntu:latest
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