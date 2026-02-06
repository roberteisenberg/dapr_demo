# Catalog API - Public, cached
resource "azurerm_api_management_api" "catalog" {
  name                = "catalog-api"
  resource_group_name = data.azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  revision            = "1"
  display_name        = "Catalog API"
  path                = "api/v1/catalog"
  protocols           = ["https"]

  subscription_required = false # Public access

  import {
    content_format = "openapi+json"
    content_value  = file("${path.module}/../api-definitions/catalog-api.json")
  }
}

# Orders API - Requires subscription key
resource "azurerm_api_management_api" "orders" {
  name                = "orders-api"
  resource_group_name = data.azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  revision            = "1"
  display_name        = "Orders API"
  path                = "api/v1/orders"
  protocols           = ["https"]

  subscription_required = true

  subscription_key_parameter_names {
    header = "X-API-Key"
    query  = "api-key"
  }

  import {
    content_format = "openapi+json"
    content_value  = file("${path.module}/../api-definitions/orders-api.json")
  }
}

# Associate APIs with self-hosted gateway
resource "azurerm_api_management_gateway_api" "catalog" {
  gateway_id = azurerm_api_management_gateway.self_hosted.id
  api_id     = azurerm_api_management_api.catalog.id
}

resource "azurerm_api_management_gateway_api" "orders" {
  gateway_id = azurerm_api_management_gateway.self_hosted.id
  api_id     = azurerm_api_management_api.orders.id
}

# Dapr Backend - routes through localhost:3500 (Dapr sidecar)
resource "azurerm_api_management_backend" "dapr" {
  name                = "dapr-backend"
  resource_group_name = data.azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  protocol            = "http"
  url                 = "http://localhost:3500"

  description = "Dapr sidecar for service invocation"
}

# API Policies
resource "azurerm_api_management_api_policy" "catalog" {
  api_name            = azurerm_api_management_api.catalog.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = data.azurerm_resource_group.rg.name

  xml_content = file("${path.module}/../policies/catalog-policy.xml")
}

resource "azurerm_api_management_api_policy" "orders" {
  api_name            = azurerm_api_management_api.orders.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = data.azurerm_resource_group.rg.name

  xml_content = file("${path.module}/../policies/orders-policy.xml")
}

# Product (subscription) for Orders API
resource "azurerm_api_management_product" "orders" {
  product_id            = "orders-product"
  api_management_name   = azurerm_api_management.apim.name
  resource_group_name   = data.azurerm_resource_group.rg.name
  display_name          = "Orders API Access"
  description           = "Subscription for Orders API"
  subscription_required = true
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product_api" "orders" {
  api_name            = azurerm_api_management_api.orders.name
  product_id          = azurerm_api_management_product.orders.product_id
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = data.azurerm_resource_group.rg.name
}

# Subscription for testing
resource "azurerm_api_management_subscription" "test" {
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = data.azurerm_resource_group.rg.name
  product_id          = azurerm_api_management_product.orders.id
  display_name        = "Test Subscription"
  state               = "active"
  allow_tracing       = true
}
