variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for tags and resource names"
  type        = string
  default     = "espocrm-devops"
}

variable "key_name" {
  description = "Name of the EXISTING EC2 key pair in AWS (the name shown in the console, without .pem)"
  type        = string
  default     = "serverkey"
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR form for SSH/Jenkins access, e.g. 102.89.1.5/32"
  type        = string
  # no default on purpose: you must set it in terraform.tfvars
}

# ---- Controller (Jenkins + Docker + Ansible) : Ubuntu 26.04 ----
variable "controller_instance_type" {
  type    = string
  default = "t3.large"
}

variable "controller_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 15
}

# ---- Ansible managed nodes : Ubuntu 24.04 ----
variable "node_count" {
  type    = number
  default = 2
}

variable "node_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "node_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 8
}
