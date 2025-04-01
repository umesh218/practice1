provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  skip_provider_registration = true # Faster initialization
}

provider "tls" {}

# Generate SSH key pair only if not provided
resource "tls_private_key" "ssh_key" {
  count     = var.ssh_public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

locals {
  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.ssh_key[0].public_key_openssh
}

# Resource Group with tags
resource "azurerm_resource_group" "my_rg" {
  name     = "nodejs-app-rg-${lower(substr(md5(local.ssh_public_key), 0, 4))}"
  location = "East US" # Consider a region closer to your users

  tags = {
    Environment = "Production"
    App         = "NodeJS"
  }

  lifecycle {
    prevent_destroy = false # Allow easier cleanup
  }
}

# Network resources optimized for single VM
module "network" {
  source              = "Azure/network/azurerm"
  version             = "~> 5.0"
  resource_group_name = azurerm_resource_group.my_rg.name
  location            = azurerm_resource_group.my_rg.location
  vnet_name           = "nodejs-vnet"
  address_space       = ["10.0.0.0/16"]
  subnet_names        = ["nodejs-subnet"]
  subnet_prefixes     = ["10.0.1.0/24"]

  nsg_ids = {
    "nodejs-subnet" = azurerm_network_security_group.my_nsg.id
  }
}

# Optimized NSG with only necessary rules
resource "azurerm_network_security_group" "my_nsg" {
  name                = "nodejs-nsg"
  location            = azurerm_resource_group.my_rg.location
  resource_group_name = azurerm_resource_group.my_rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "NodeJS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Public IP with DNS label
resource "azurerm_public_ip" "my_public_ip" {
  name                = "nodejs-ip"
  location            = azurerm_resource_group.my_rg.location
  resource_group_name = azurerm_resource_group.my_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "nodejs-app-${lower(substr(md5(local.ssh_public_key), 0, 4))}"
}

# Network Interface with accelerated networking
resource "azurerm_network_interface" "my_nic" {
  name                          = "nodejs-nic"
  location                      = azurerm_resource_group.my_rg.location
  resource_group_name           = azurerm_resource_group.my_rg.name
  enable_accelerated_networking = true # Faster networking

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.network.vnet_subnets[0]
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.my_public_ip.id
  }
}

# Linux VM with cloud-init for faster provisioning
resource "azurerm_linux_virtual_machine" "my_vm" {
  name                            = "nodejs-vm"
  location                        = azurerm_resource_group.my_rg.location
  resource_group_name             = azurerm_resource_group.my_rg.name
  size                            = "Standard_B2s" # Slightly larger for better performance
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.my_nic.id]
  priority                        = "Spot" # Cost savings (optional)
  eviction_policy                 = "Deallocate"

  admin_ssh_key {
    username   = "azureuser"
    public_key = local.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS" # Better performance
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy" # Ubuntu 22.04 LTS
    sku       = "22_04-lts-gen2"              # Gen2 for better performance
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    docker_compose = filebase64("${path.module}/docker-compose.yml")
  }))

  # Pre-install Docker and app during provisioning
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    app_directory = "/opt/nodejs-app"
  }))

  lifecycle {
    ignore_changes = [
      custom_data,
      user_data
    ]
  }
}

# Outputs with sensitive data marked
output "public_ip" {
  value       = azurerm_public_ip.my_public_ip.ip_address
  description = "Public IP address of the VM"
}

output "ssh_private_key" {
  value       = var.ssh_public_key == "" ? tls_private_key.ssh_key[0].private_key_pem : null
  sensitive   = true
  description = "Generated SSH private key (if not provided)"
}

output "app_url" {
  value       = "http://${azurerm_public_ip.my_public_ip.domain_name_label}.${azurerm_public_ip.my_public_ip.location}.cloudapp.azure.com:8080"
  description = "Application URL"
}
