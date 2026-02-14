# Reference existing resource group from Phase 6/8
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

# API Management Instance
resource "azurerm_api_management" "apim" {
  name                = var.apim_name
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email

  # Developer SKU - full policy support including built-in cache.
  # Consumption SKU also works (no self-hosted gateway needed) but lacks built-in cache.
  sku_name = "Developer_1"

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}
