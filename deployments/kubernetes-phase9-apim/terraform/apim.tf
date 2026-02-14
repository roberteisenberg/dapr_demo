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

# Backend - routes through nginx-ingress in AKS (which has a Dapr sidecar)
# APIM cloud gateway cannot use localhost:3500 (no Dapr sidecar in Azure).
# Instead, it routes to the nginx-ingress public FQDN, which then uses its
# Dapr sidecar for service invocation with mTLS and access control.
resource "azurerm_api_management_backend" "nginx_ingress" {
  name                = "nginx-ingress-backend"
  resource_group_name = data.azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  protocol            = "http"
  url                 = "https://${var.nginx_ingress_fqdn}"

  description = "nginx-ingress in AKS with Dapr sidecar (app-id: api-gateway)"

  # Let's Encrypt certs are trusted by Azure. No need to disable TLS validation.
  # If using self-signed certs, add: tls { validate_certificate_chain = false; validate_certificate_name = false }
}

# API Policies
resource "azurerm_api_management_api_policy" "catalog" {
  api_name            = azurerm_api_management_api.catalog.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = data.azurerm_resource_group.rg.name

  xml_content = file("${path.module}/../policies/catalog-policy.xml")

  depends_on = [azurerm_api_management_backend.nginx_ingress]
}

resource "azurerm_api_management_api_policy" "orders" {
  api_name            = azurerm_api_management_api.orders.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = data.azurerm_resource_group.rg.name

  xml_content = file("${path.module}/../policies/orders-policy.xml")

  depends_on = [azurerm_api_management_backend.nginx_ingress]
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
