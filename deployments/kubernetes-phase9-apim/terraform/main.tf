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

  # Developer SKU required for self-hosted gateway (Consumption doesn't support it)
  sku_name = "Developer_1"

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Self-Hosted Gateway
resource "azurerm_api_management_gateway" "self_hosted" {
  name              = var.gateway_name
  api_management_id = azurerm_api_management.apim.id
  description       = "Self-hosted gateway in AKS with Dapr sidecar"

  location_data {
    name   = "AKS Cluster"
    region = var.location
  }
}
