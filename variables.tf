# variables.tf

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "<YOUR_PREFERRED_REGION>"
}

variable "project_name" {
  description = "A unique name for your project, used as a prefix for resources."
  type        = string
  default     = "<YOUR_PROJECT_NAME>"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "The CIDR block for the public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_untrust_subnet_cidr" {
  description = "The CIDR block for the private untrust subnet (VM-Series eth0/eth1)."
  type        = string
  default     = "10.0.10.0/24"
}

variable "private_trust_subnet_cidr" {
  description = "The CIDR block for the private trust subnet (VM-Series eth2, Ubuntu)."
  type        = string
  default     = "10.0.20.0/24"
}

variable "panorama_instance_type" {
  description = "The EC2 instance type for Panorama."
  type        = string
  default     = "c5.4xlarge" # Recommended by Palo Alto
}

variable "vmseries_instance_type" {
  description = "The EC2 instance type for VM-Series Firewall."
  type        = string
  default     = "m5.xlarge" # A common choice for lab environments
}

variable "ubuntu_instance_type" {
  description = "The EC2 instance type for the Ubuntu tester instance."
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "The name of the EC2 Key Pair to use for SSH access."
  type        = string
  default     = "<YOUR_KEY_PAIR_NAME>" # Change this to your desired key pair name
}

variable "allowed_ssh_cidr" {
  description = "The CIDR block allowed to SSH into instances (e.g., your public IP address/32)."
  type        = string
  default     = "0.0.0.0/0" # WARNING: For lab only, restrict to your IP in production!
}
