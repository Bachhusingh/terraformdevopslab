terraform {
  backend "azurerm" {
    resource_group_name  = "mydemyrg01"
    storage_account_name = "testapp07storage"  # <- use module output
    container_name       = "mytestcontainer01"
    key                  = "dev.terraform.tfstate"
  }
}
