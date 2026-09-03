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

# 2. Security Group Configuration
resource "aws_security_group" "starrocks_sg" {
  name_prefix = "starrocks-sg-"
  description = "Allow SSH, MySQL client, and HTTP access to StarRocks"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # StarRocks MySQL Query Port
  ingress {
    from_port   = 9030
    to_port     = 9030
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # StarRocks Web HTTP Port
  ingress {
    from_port   = 8030
    to_port     = 8030
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

# 3. AWS EC2 Instance Definition
resource "aws_instance" "starrocks_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  # Expand EBS Root Disk to 20GB to fit Docker containers
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

              # Enable 4GB Swap Space for t3.micro memory stability
              fallocate -l 4G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              systemctl start docker
              systemctl enable docker

              # 1. Run Lightweight StarRocks Frontend (FE)
              docker run -d \
                --name starrocks-fe \
                --net=host \
                --restart always \
                -e HOST_TYPE=IP \
                -e JAVA_OPTS="-Xmx768m -Xms768m" \
                starrocks/fe-ubuntu:latest \
                /opt/starrocks/fe/bin/start_fe.sh

              # 2. Run Lightweight StarRocks Backend (BE)
              docker run -d \
                --name starrocks-be \
                --net=host \
                --restart always \
                starrocks/be-ubuntu:latest \
                /opt/starrocks/be/bin/start_be.sh

              # 3. Wait 20 seconds for FE boot, then automatically register BE node
              sleep 20
              mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND '127.0.0.1:9050';"
              EOF

  tags = {
    Name = "StarRocks-DataTeam-Test"
  }
}

# 4. Outputs
output "public_ip" {
  value       = aws_instance.starrocks_server.public_ip
  description = "Public IP of the StarRocks instance"
}

output "data_team_connection_string" {
  value       = "mysql -h ${aws_instance.starrocks_server.public_ip} -P 9030 -u root"
  description = "Share this connection command with external team members"
}