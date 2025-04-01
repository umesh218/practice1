provider "azurerm" {
  features {}
}

provider "tls" {}

variable "ssh_public_key" {
  description = "The SSH public key for VM"
  type        = string
}

# Resource Group
resource "azurerm_resource_group" "my_rg" {
  name     = "my-resource-group"
  location = "East US"
}

# Virtual Network
resource "azurerm_virtual_network" "my_vnet" {
  name                = "my-vnet"
  location            = azurerm_resource_group.my_rg.location
  resource_group_name = azurerm_resource_group.my_rg.name
  address_space       = ["10.0.0.0/16"]
}

# Subnet
resource "azurerm_subnet" "my_subnet" {
  name                 = "my-subnet"
  resource_group_name  = azurerm_resource_group.my_rg.name
  virtual_network_name = azurerm_virtual_network.my_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group (NSG)
resource "azurerm_network_security_group" "my_nsg" {
  name                = "my-nsg"
  location            = azurerm_resource_group.my_rg.location
  resource_group_name = azurerm_resource_group.my_rg.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowNodeJS"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Public IP
resource "azurerm_public_ip" "my_public_ip" {
  name                = "my-public-ip"
  location            = azurerm_resource_group.my_rg.location
  resource_group_name = azurerm_resource_group.my_rg.name
  allocation_method   = "Static"
}

# Network Interface
resource "azurerm_network_interface" "my_nic" {
  name                = "my-nic"
  location            = azurerm_resource_group.my_rg.location
  resource_group_name = azurerm_resource_group.my_rg.name

  ip_configuration {
    name                          = "my-nic-config"
    subnet_id                     = azurerm_subnet.my_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.my_public_ip.id
  }
}

# Associate NSG with NIC
resource "azurerm_network_interface_security_group_association" "nsg_association" {
  network_interface_id      = azurerm_network_interface.my_nic.id
  network_security_group_id = azurerm_network_security_group.my_nsg.id
}

# SSH Key Pair (Private and Public)
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "azurerm_ssh_public_key" "my_ssh_key" {
  name                = "my-ssh-key"
  public_key          = tls_private_key.ssh_key.public_key_openssh
  resource_group_name = azurerm_resource_group.my_rg.name
  location            = azurerm_resource_group.my_rg.location
}

# Virtual Machine
resource "azurerm_linux_virtual_machine" "my_vm" {
  name                = "my-vm"
  location            = azurerm_resource_group.my_rg.location
  resource_group_name = azurerm_resource_group.my_rg.name
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  network_interface_ids = [azurerm_network_interface.my_nic.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = azurerm_ssh_public_key.my_ssh_key.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  custom_data = base64encode(file("${path.module}/install-docker.sh"))
}

# Output SSH Private Key and Public IP
output "ssh_private_key" {
  value     = tls_private_key.ssh_key.private_key_pem
  sensitive = true
}

output "public_ip" {
  value = azurerm_public_ip.my_public_ip.ip_address
}
