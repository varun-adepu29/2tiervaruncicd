#ResourceGroup
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

#NSG
resource "azurerm_network_security_group" "app_nsg" {
  name                = "Vappnsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    source_port_range          = "*"
  }

  security_rule {
    name                       = "Allow-Flask"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    destination_port_range     = "5000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    source_port_range          = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    source_port_range          = "*"
  }
}

#PublicIp
resource "azurerm_public_ip" "public_ip" {
  name                = "MyVAppVM-ip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

#NIC
resource "azurerm_network_interface" "nic" {
  name                = "vapp-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

#NSG_Assosiate
resource "azurerm_network_interface_security_group_association" "assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.app_nsg.id
}

#Virtual_Machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "MyVAppVM"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  size                = "Standard_D2s_v3"

  admin_username = var.admin_username
  admin_password = var.admin_password
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

custom_data = base64encode(templatefile("${path.module}/setup.sh", {
  DB_HOST     = azurerm_mysql_flexible_server.mysql.fqdn
  DB_USER     = var.mysql_admin
  DB_PASSWORD = var.mysql_password
  DB_NAME     = "studentdb"
  APP_DIR     = "/home/azureuser/student-app"   # ✅ ADD THIS
}))
}

#azurerm_mysql_flexible_server
resource "azurerm_mysql_flexible_server" "mysql" {
  name                   = "varundatabase54"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = var.location

  administrator_login    = var.mysql_admin
  administrator_password = var.mysql_password

  sku_name = "B_Standard_B1ms"
  version  = "8.4"

  storage {
    size_gb = 20
  }
}

#azurerm_mysql_flexible_server_firewall_rule
resource "azurerm_mysql_flexible_server_firewall_rule" "allow_vm" {
  name                = "Allow-VM-IP"
  server_name         = azurerm_mysql_flexible_server.mysql.name
  resource_group_name = azurerm_resource_group.rg.name

  start_ip_address = azurerm_public_ip.public_ip.ip_address
  end_ip_address   = azurerm_public_ip.public_ip.ip_address

  depends_on = [
    azurerm_public_ip.public_ip,
    azurerm_mysql_flexible_server.mysql
  ]
}




