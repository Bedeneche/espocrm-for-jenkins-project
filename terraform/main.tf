terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------- Default VPC ----------
data "aws_vpc" "default" {
  default = true
}

# ---------- AMIs (Canonical = 099720109477) ----------
data "aws_ami" "ubuntu_2604" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-*-26.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------- Security groups ----------
resource "aws_security_group" "controller" {
  name        = "${var.project_name}-controller-sg"
  description = "Jenkins/Ansible controller"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "Jenkins UI from my IP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-controller-sg" }
}

resource "aws_security_group" "nodes" {
  name        = "${var.project_name}-nodes-sg"
  description = "Ansible managed nodes running EspoCRM"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "SSH from controller"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.controller.id]
  }

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "EspoCRM web (HTTP)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-nodes-sg" }
}

# ---------- Controller: Ubuntu 26.04, t3.large, 15 GB ----------
resource "aws_instance" "controller" {
  ami                    = data.aws_ami.ubuntu_2604.id
  instance_type          = var.controller_instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.controller.id]

  user_data                   = file("${path.module}/../scripts/install_jenkins_docker.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = var.controller_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = { Name = "${var.project_name}-controller" }
}

# ---------- Ansible nodes: Ubuntu 24.04, t3.micro, 8 GB ----------
resource "aws_instance" "node" {
  count                  = var.node_count
  ami                    = data.aws_ami.ubuntu_2404.id
  instance_type          = var.node_instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.nodes.id]

  root_block_device {
    volume_size           = var.node_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = { Name = "${var.project_name}-node${count.index + 1}" }
}

# ---------- Generate the Ansible inventory from real IPs ----------
resource "local_file" "inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content = templatefile("${path.module}/inventory.tftpl", {
    node_ips = aws_instance.node[*].private_ip
  })
}

# ---------- Outputs ----------
output "controller_public_ip" {
  value = aws_instance.controller.public_ip
}

output "jenkins_url" {
  value = "http://${aws_instance.controller.public_ip}:8080"
}

output "node_public_ips" {
  value = aws_instance.node[*].public_ip
}

output "node_private_ips" {
  value = aws_instance.node[*].private_ip
}

output "ssh_controller" {
  value = "ssh -i serverkey.pem ubuntu@${aws_instance.controller.public_ip}"
}
