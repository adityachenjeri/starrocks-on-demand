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

# 1. Firewall Rule (Security Group)
resource "aws_security_group" "starrocks_sg" {
  name        = "starrocks-on-demand-sg"
  description = "Allow MySQL access to StarRocks"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # StarRocks MySQL Protocol Port
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

# 2. AWS EC2 Server
resource "aws_instance" "starrocks_server" {
  ami           = "ami-0c7217cdde317cfec" # Ubuntu 22.04 LTS (us-east-1)
  instance_type = "t3.large"              # 2 vCPU, 8GB RAM

  security_groups = [aws_security_group.starrocks_sg.name]

  # User Data: Automatically starts StarRocks in Docker on launch
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker

              # Run all-in-one StarRocks container directly
              docker run -p 9030:9030 -p 8030:8030 -p 8040:8040 -itd --name starrocks starrocks/all-in-1-ubuntu
              EOF

  tags = {
    Name = "StarRocks-DataTeam-Test"
  }
}

# 3. Connection Output Link for Data Team
output "data_team_connection_string" {
  value       = "mysql -h ${aws_instance.starrocks_server.public_ip} -P 9030 -u root"
  description = "Share this connection command with the Data Analysis team"
}