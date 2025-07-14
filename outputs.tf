# outputs.tf

output "panorama_public_ip" {
  description = "The public IP address of the Panorama instance."
  value       = aws_instance.panorama.public_ip
}

output "panorama_private_ip" {
  description = "The private IP address of the Panorama instance."
  value       = aws_instance.panorama.private_ip
}

output "vmseries_management_ip" {
  description = "The private IP address of the VM-Series management interface (eth0)."
  value       = aws_network_interface.vmseries_eth0.private_ip
}

output "vmseries_untrust_ip" {
  description = "The private IP address of the VM-Series untrust interface (ethernet1/1)."
  value       = aws_network_interface.vmseries_eth1.private_ip
}

output "vmseries_trust_ip" {
  description = "The private IP address of the VM-Series trust interface (ethernet1/2)."
  value       = aws_network_interface.vmseries_eth2.private_ip
}

output "ubuntu_private_ip" {
  description = "The private IP address of the Ubuntu tester instance."
  value       = aws_instance.ubuntu_tester.private_ip
}

output "ssh_command_panorama" {
  description = "SSH command to connect to Panorama."
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem admin@${aws_instance.panorama.public_ip}"
}

output "ssh_command_ubuntu" {
  description = "SSH command to connect to Ubuntu tester instance (from a machine with access to the private network, e.g., bastion or direct connect/VPN)."
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ubuntu@${aws_instance.ubuntu_tester.private_ip}"
}

output "bastion_public_ip" {
  description = "The public IP address of the Bastion Host."
  value       = aws_instance.bastion_host.public_ip
}

output "ssh_command_bastion" {
  description = "SSH command to connect to the Bastion Host."
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ubuntu@${aws_instance.bastion_host.public_ip}"
}

output "ssh_command_vmseries_via_bastion" {
  description = "SSH command to connect to VM-Series via Bastion Host."
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem -o ProxyJump=ubuntu@${aws_instance.bastion_host.public_ip} admin@${aws_network_interface.vmseries_eth0.private_ip}"
}

output "ssh_command_ubuntu_via_bastion" {
  description = "SSH command to connect to Ubuntu Tester via Bastion Host."
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem -o ProxyJump=ubuntu@${aws_instance.bastion_host.public_ip} ubuntu@${aws_instance.ubuntu_tester.private_ip}"
}
