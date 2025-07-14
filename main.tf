# main.tf

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
}

# Data source for the latest Ubuntu AMI
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

# Data source for the latest Palo Alto Networks Panorama AMI (BYOL)
data "aws_ami" "panorama" {
  most_recent = true
  filter {
    name   = "name"
    values = ["*Panorama*"]
  }
  filter {
    name   = "product-code"
    values = ["eclz7j04vu9lf8ont8ta3n17o"]
  }
  owners = ["679593333241"] # Palo Alto Networks
}

# Data source for the latest Palo Alto Networks VM-Series AMI (BYOL)
data "aws_ami" "vmseries" {
  most_recent = true
  filter {
    name   = "name"
    values = ["*PA-VM-AWS*"]
  }
  filter {
    name   = "product-code"
    values = ["6njl1pau431dv1qxipg63mvah"]
  }
  owners = ["679593333241"] # Palo Alto Networks
}

# VPC
resource "aws_vpc" "lab_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-VPC"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "lab_igw" {
  vpc_id = aws_vpc.lab_vpc.id

  tags = {
    Name = "${var.project_name}-IGW"
  }
}

# Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.lab_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-Public-Subnet"
  }
}

# Private Untrust Subnet (for VM-Series untrust/mgmt interface)
resource "aws_subnet" "private_untrust_subnet" {
  vpc_id            = aws_vpc.lab_vpc.id
  cidr_block        = var.private_untrust_subnet_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-Private-Untrust-Subnet"
  }
}

# Private Trust Subnet (for VM-Series trust interface and Ubuntu instance)
resource "aws_subnet" "private_trust_subnet" {
  vpc_id            = aws_vpc.lab_vpc.id
  cidr_block        = var.private_trust_subnet_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-Private-Trust-Subnet"
  }
}

# NAT Gateway
resource "aws_eip" "nat_gateway_eip" {
  domain = "vpc" 
}

resource "aws_nat_gateway" "lab_nat_gateway" {
  allocation_id = aws_eip.nat_gateway_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "${var.project_name}-NAT-Gateway"
  }
  depends_on = [aws_internet_gateway.lab_igw]
}

# Route Tables

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.lab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab_igw.id
  }

  tags = {
    Name = "${var.project_name}-Public-RT"
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Untrust Route Table (default route to NAT Gateway for management updates etc.)
resource "aws_route_table" "untrust_rt" {
  vpc_id = aws_vpc.lab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.lab_nat_gateway.id
  }

  tags = {
    Name = "${var.project_name}-Untrust-RT"
  }
}

resource "aws_route_table_association" "untrust_rt_assoc" {
  subnet_id      = aws_subnet.private_untrust_subnet.id
  route_table_id = aws_route_table.untrust_rt.id
}

# Trust Route Table (default route to VM-Series eth1/2)
resource "aws_route_table" "trust_rt" {
  vpc_id = aws_vpc.lab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    # This will be updated after the VM-Series eth1/2 ENI is created
    # The actual next hop will be the private IP of eth1/2
    network_interface_id = aws_network_interface.vmseries_eth2.id
  }

  tags = {
    Name = "${var.project_name}-Trust-RT"
  }
}

resource "aws_route_table_association" "trust_rt_assoc" {
  subnet_id      = aws_subnet.private_trust_subnet.id
  route_table_id = aws_route_table.trust_rt.id
}

# Security Groups

# Security Group for Panorama Management
resource "aws_security_group" "panorama_sg" {
  name        = "${var.project_name}-Panorama-SG"
  description = "Allow SSH and HTTPS to Panorama"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr] # Restrict to your IP or bastion host
    description = "SSH from management"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr] # Restrict to your IP or bastion host
    description = "HTTPS from management"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-Panorama-SG"
  }
}

# Security Group for VM-Series Management Interface (eth0)
resource "aws_security_group" "vmseries_mgmt_sg" {
  name        = "${var.project_name}-VMSeries-Mgmt-SG"
  description = "Allow SSH/HTTPS to VM-Series Mgmt from Panorama and allowed CIDR"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr, "${aws_instance.panorama.private_ip}/32"]
    security_groups = [aws_security_group.bastion_sg.id]
    description = "SSH from management and Panorama"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr, "${aws_instance.panorama.private_ip}/32"]
    security_groups = [aws_security_group.bastion_sg.id]
    description = "HTTPS from management and Panorama"
  }

  # Allow Panorama to communicate with VM-Series for management plane
  ingress {
    from_port   = 3978 # Panorama to VM-Series communication
    to_port     = 3978
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.panorama.private_ip}/32"]
    description = "Panorama communication to VM-Series"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Allow outbound for updates, Panorama registration
  }

  tags = {
    Name = "${var.project_name}-VMSeries-Mgmt-SG"
  }
}

# Security Group for VM-Series Untrust Interface (ethernet1/1)
resource "aws_security_group" "vmseries_untrust_sg" {
  name        = "${var.project_name}-VMSeries-Untrust-SG"
  description = "Allow traffic to/from VM-Series Untrust interface"
  vpc_id      = aws_vpc.lab_vpc.id

  # Fixed: Reference subnet CIDR to break cycle
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_subnet.private_trust_subnet.cidr_block] # Allow all traffic from the trust subnet for return path
    description = "Allow all from Trust Subnet (for return traffic)"
  }

  # Allow outbound to anywhere (internet)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-VMSeries-Untrust-SG"
  }
}

# Security Group for VM-Series Trust Interface (ethernet1/2)
resource "aws_security_group" "vmseries_trust_sg" {
  name        = "${var.project_name}-VMSeries-Trust-SG"
  description = "Allow traffic to/from VM-Series Trust interface"
  vpc_id      = aws_vpc.lab_vpc.id

  # Allow all inbound from the Trust Subnet (where Ubuntu resides)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_subnet.private_trust_subnet.cidr_block]
    description = "Allow all from Trust Subnet"
  }

  # Fixed: Reference subnet CIDR to break cycle
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_subnet.private_untrust_subnet.cidr_block] # Allow all traffic to the untrust subnet
    description = "Allow all to Untrust Subnet"
  }

  tags = {
    Name = "${var.project_name}-VMSeries-Trust-SG"
  }
}

# Security Group for Ubuntu Instance
resource "aws_security_group" "ubuntu_sg" {
  name        = "${var.project_name}-Ubuntu-SG"
  description = "Allow SSH to Ubuntu instance"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr] # Restrict to your IP or bastion host
    security_groups = [aws_security_group.bastion_sg.id]
    description = "SSH from management"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Allow outbound for updates/testing
  }

  tags = {
    Name = "${var.project_name}-Ubuntu-SG"
  }
}

# Security Group for Bastion Server
resource "aws_security_group" "bastion_sg" {
  name		= "${var.project_name}-Bastion-SG"
  description   = "Allow SSH to Bastion host from allowed CIDR"
  vpc_id	= aws_vpc.lab_vpc.id

  ingress {
    from_port	= 22
    to_port	= 22
    protocol 	= "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
    description = "SSH from management"
  }

  egress {
    from_port	= 0
    to_port	= 0
    protocol	= "-1"
    cidr_blocks	= ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-Bastion-SG"
  }
}

# EC2 Key Pair
data "aws_key_pair" "lab_key_pair" {
  key_name   = var.key_pair_name
}

# Panorama Instance
resource "aws_instance" "panorama" {
  ami                         = data.aws_ami.panorama.id
  instance_type               = var.panorama_instance_type
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.panorama_sg.id]
  key_name                    = data.aws_key_pair.lab_key_pair.key_name
  associate_public_ip_address = true # Automatically assign a public IP

  root_block_device {
    volume_size = 200 # Minimum recommended for Panorama
  }

  tags = {
    Name = "${var.project_name}-Panorama"
  }
}

# VM-Series Firewall Instance
resource "aws_instance" "vmseries" {
  ami                         = data.aws_ami.vmseries.id
  instance_type               = var.vmseries_instance_type
  key_name                    = data.aws_key_pair.lab_key_pair.key_name
  disable_api_termination     = false # Set to true in production

  # Management Interface (eth0)
  network_interface {
    network_interface_id = aws_network_interface.vmseries_eth0.id
    device_index         = 0
  }

  # Data Plane Interfaces (ethernet1/1 and ethernet1/2)
  # These are attached as secondary network interfaces
  network_interface {
    network_interface_id = aws_network_interface.vmseries_eth1.id
    device_index         = 1
  }

  network_interface {
    network_interface_id = aws_network_interface.vmseries_eth2.id
    device_index         = 2
  }

  # User data for initial configuration (e.g., setting management IP, default route, Panorama IP)
  user_data = <<-EOF
    #!/bin/bash
    # Wait for the network interfaces to be up
    sleep 60

    # Configure the management interface (eth0)
    # The VM-Series typically uses eth0 as management.
    # We need to ensure it has the correct IP and route to Panorama.
    # For initial setup, we can assume DHCP on eth0.
    # The important part is to allow Panorama to reach it.

    # Initial configuration for VM-Series (CLI commands)
    # This is a basic example. For full automation, consider bootstrapping.
    # For a lab, you'll likely configure this manually or via Panorama after deployment.
    # However, for the VM-Series to reach Panorama, it needs a default route.
    # This user_data is more for initial network setup if needed, but for PAN-OS,
    # it's usually done via CLI/GUI after boot or Panorama bootstrap.

    # Example of basic CLI commands for initial setup (not fully automated here)
    # This would typically be done via bootstrap or manual config after instance is up.
    # Reference: https://docs.paloaltonetworks.com/vm-series/11-0/vm-series-deployment/set-up-the-vm-series-firewall-on-aws/deploy-the-vm-series-firewall-on-aws/perform-initial-configuration-of-the-vm-series-firewall-on-aws
    # The management interface (eth0) will get its IP via DHCP from the subnet.
    # The data plane interfaces (ethernet1/1, ethernet1/2) need to be configured inside PAN-OS.
    # For Panorama to manage the VM-Series, the VM-Series needs to be able to reach Panorama's management IP.
    # Since Panorama is in the public subnet and VM-Series mgmt is in private-untrust,
    # the VM-Series mgmt will use the untrust_rt which points to NAT Gateway.
    # This allows the VM-Series to reach Panorama's public IP.

    # For a lab, you'll login to Panorama, add the VM-Series, and push config.
    # The user_data can be used for very basic network settings if DHCP isn't enough,
    # but PAN-OS handles its own network configuration internally.
    echo "VM-Series instance started. Manual configuration or Panorama bootstrap will be needed."
  EOF

  tags = {
    Name = "${var.project_name}-VMSeries"
  }
}

# Network Interfaces for VM-Series
# eth0 (Management)
resource "aws_network_interface" "vmseries_eth0" {
  subnet_id       = aws_subnet.private_untrust_subnet.id
  security_groups = [aws_security_group.vmseries_mgmt_sg.id]
  source_dest_check = true # Management interface usually has source/dest check enabled

  tags = {
    Name = "${var.project_name}-VMSeries-eth0-Mgmt"
  }
}

# ethernet1/1 (Untrust/External)
resource "aws_network_interface" "vmseries_eth1" {
  subnet_id       = aws_subnet.private_untrust_subnet.id
  security_groups = [aws_security_group.vmseries_untrust_sg.id]
  source_dest_check = false # Disable source/destination check for data plane interfaces

  tags = {
    Name = "${var.project_name}-VMSeries-eth1-Untrust"
  }
}

# ethernet1/2 (Trust/Internal)
resource "aws_network_interface" "vmseries_eth2" {
  subnet_id       = aws_subnet.private_trust_subnet.id
  security_groups = [aws_security_group.vmseries_trust_sg.id]
  source_dest_check = false # Disable source/destination check for data plane interfaces

  tags = {
    Name = "${var.project_name}-VMSeries-eth2-Trust"
  }
}

# Ubuntu Instance
resource "aws_instance" "ubuntu_tester" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.ubuntu_instance_type
  subnet_id                   = aws_subnet.private_trust_subnet.id
  vpc_security_group_ids      = [aws_security_group.ubuntu_sg.id]
  key_name                    = data.aws_key_pair.lab_key_pair.key_name
  associate_public_ip_address = false # No public IP for internal host

  user_data = <<-EOF
    #!/bin/bash
    sudo apt-get update -y
    sudo apt-get install -y curl jq
    echo "Ubuntu instance ready for testing."
  EOF

  tags = {
    Name = "${var.project_name}-Ubuntu-Tester"
  }
}

# Bastion Host instance
resource "aws_instance" "bastion_host" {
  ami			= data.aws_ami.ubuntu.id
  instance_type		= var.ubuntu_instance_type
  subnet_id		= aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name		= data.aws_key_pair.lab_key_pair.key_name
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    sudo apt-get update -y
    sudo apt-get install -y openssh-client
    echo "Bastion Host ready."
  EOF

  tags = {
    Name = "${var.project_name}-Bastion-Host"
  }
}
