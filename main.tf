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

resource "aws_instance" "starrocks_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

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

              fallocate -l 4G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              systemctl start docker
              systemctl enable docker

              docker run -d \
                --name starrocks-fe \
                --net=host \
                --restart always \
                -e HOST_TYPE=IP \
                -e JAVA_OPTS="-Xmx768m -Xms768m" \
                starrocks/fe-ubuntu:latest \
                /opt/starrocks/fe/bin/start_fe.sh
              EOF

  tags = {
    Name = "StarRocks-DataTeam-Test"
  }
}

output "data_team_connection_string" {
  value       = "mysql -h ${aws_instance.starrocks_server.public_ip} -P 9030 -u root"
  description = "Share this connection command with the Data Analysis team"
}