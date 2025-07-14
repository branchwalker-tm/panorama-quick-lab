# panorama-quick-lab

A simple Terraform script to quickly create a lab environment that contains a Palo Alto Networks VM-Series firewall with an Ubuntu box behind it, a virtual Panorama device, and an Ubuntu bastion server.

## Requirements

1. Terraform must be installed
2. Must have your `AWS_ACCES_KEY_ID` and `AWS_SECRET_ACCESS_KEY` set as environment variables
3. AWS CLI must be installed (required for Terraform to work)
4. A valid keypair in AWS

## How to use

Add your preferrred AWS region, your key pair name, and a project name in the `variables.tf` file. Then run `terraform plan` and `terraform apply` in your working directory.

Once the environment has been created your will need to register your Palo Alto Networks devices, add the VM-series firewall as a managed device in Panorama, and configure the VM-series to your heart's conent. ***IMPORTANT*** You'll need to configure a tunnel on your local machine and access the VM-series GUI by navigating to `https://localhost:8443`. You can configure the tunnel by running:
`ssh -i ~/.ssh/my-lab-key.pem -L 8443:<VM_Series_Management_Private_IP>:443 ubuntu@<Bastion_Public_IP>` 
