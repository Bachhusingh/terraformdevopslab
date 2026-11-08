resource "azurerm_resource_group" "bks" {
  name     = var.resource_group
  location = var.location
  tags  = var.tag

}

/*resource "azurerm_virtual_network" "vnet" {
  name                = "myvent01"
  resource_group_name = azurerm_resource_group.bks.name
  location            = azurerm_resource_group.bks.location
  address_space       = ["10.0.0.0/16"]

}

resource "azurerm_subnet" "subnet" {
  name                 = "mytestsubnet01"
  resource_group_name  = azurerm_resource_group.bks.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/29"]

}*/


resource "azurerm_storage_account" "storage" {
  name                     = "${var.Application}${var.teamnumber}storage"
  resource_group_name      = azurerm_resource_group.bks.name
  location                 = azurerm_resource_group.bks.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags = var.tag

}

resource "azurerm_storage_container" "cont" {
  name = "mytestcontainer01"
  storage_account_id = azurerm_storage_account.storage.id
  container_access_type = "private"
  
}