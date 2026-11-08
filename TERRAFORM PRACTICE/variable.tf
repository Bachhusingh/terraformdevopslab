variable "resource_group" {
    type = string
    description = "Provide resource group name"
    default = "mydemyrg01"
  
}

variable "location" {
    type = string
    description = "Provide location"
    default = "Central India"
  
}

variable "storage" {
    type = string
    description = "Provide storage account name"
    default = "myteststorage01bks"
  
}

variable "tag" {
    type = map(string)
    description = "Provide tag details"
    default = {
        environment = "test"
        tag="test"
    }
  
}

variable "teamnumber" {
    type = string
    description = "Provide team number"
    default = "07"
  
}

variable "Application" {
    type = string
    description = "Provide application name"
    default = "testapp"
  
}

