resource "azurerm_resource_group" "bks1" {
  name     = "${var.Application}-${var.teamnumber}-rg"
  location = var.location
  tags  = var.tag

}