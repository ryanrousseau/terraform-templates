terraform {

  required_version = ">=0.12"
  
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~>1.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
  }
  
  backend "azurerm" {
    resource_group_name  = "demo.octopus.app"
    storage_account_name = "octodemotfstate"
    container_name       = "terraform-state"
    key                  = "#{Project.Terraform.State.Key}.tfstate"
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {
}

variable "octopus_azure_resource_group" {
    type = string
    default = "#{Project.Azure.ResourceGroup}"
}

variable "octopus_azure_vm_admin_username" {
    type = string
    sensitive = true
    default = "#{Project.VM.Admin.Username}"
}

variable "octopus_azure_vm_name" {
    type = string
    default = "#{Project.VM.Name}"
}

data "azurerm_resource_group" "demo" {
    name = var.octopus_azure_resource_group
}

data "azurerm_subnet" "demo" {
  name = "default"
  virtual_network_name = "demo.octopus.app-vnet"
  resource_group_name = data.azurerm_resource_group.demo.name
}

data "azurerm_network_security_group" "tentacle" {
  name = "tentacle-only-nsg"
  resource_group_name = data.azurerm_resource_group.demo.name
}

resource "random_pet" "ssh_key_name" {
  prefix    = "ssh"
  separator = ""
}

resource "azapi_resource_action" "ssh_public_key_gen" {
  type        = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  resource_id = azapi_resource.ssh_public_key.id
  action      = "generateKeyPair"
  method      = "POST"

  response_export_values = ["publicKey", "privateKey"]
}

resource "azapi_resource" "ssh_public_key" {
  type      = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  name      = random_pet.ssh_key_name.id
  location  = data.azurerm_resource_group.demo.location
  parent_id = data.azurerm_resource_group.demo.id
}

output "key_data" {
  value = azapi_resource_action.ssh_public_key_gen.output.publicKey
}

resource "azurerm_network_interface" "example" {
  name                = "${var.octopus_azure_vm_name}-nic"
  location            = data.azurerm_resource_group.demo.location
  resource_group_name = data.azurerm_resource_group.demo.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.demo.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "example" {
  network_interface_id      = azurerm_network_interface.example.id
  network_security_group_id = data.azurerm_network_security_group.tentacle.id
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "server" {
  name                  = var.octopus_azure_vm_name
  location              = data.azurerm_resource_group.demo.location
  resource_group_name   = data.azurerm_resource_group.demo.name
  network_interface_ids = [azurerm_network_interface.example.id]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "${var.octopus_azure_vm_name}-disk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  computer_name  = var.octopus_azure_vm_name
  admin_username = var.octopus_azure_vm_admin_username

  admin_ssh_key {
    username   = var.octopus_azure_vm_admin_username
    public_key = azapi_resource_action.ssh_public_key_gen.output.publicKey
  }
}

resource "azurerm_virtual_machine_extension" "demo" {
  name                 = "CustomScript"
  virtual_machine_id   = azurerm_linux_virtual_machine.server.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
  {
    "fileUris": ["https://raw.githubusercontent.com/ryanrousseau/terraform-templates/main/scripts/register-polling-tentacle.sh"],
    "commandToExecute": "./register-polling-tentacle.sh \"#{Project.Octopus.Domain}\" \"#{Project.Octopus.ApiKey}\" \"#{Octopus.Space.Name}\" \"#{Octopus.Environment.Name}\" \"#{Project.VM.Roles}\" \"#{Octopus.Deployment.Tenant.Id}\""
  }
SETTINGS
}
