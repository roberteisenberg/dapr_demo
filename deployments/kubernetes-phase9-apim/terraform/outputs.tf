output "apim_name" {
  description = "API Management instance name"
  value       = azurerm_api_management.apim.name
}

output "apim_gateway_url" {
  description = "API Management gateway URL"
  value       = azurerm_api_management.apim.gateway_url
}

output "gateway_name" {
  description = "Self-hosted gateway name"
  value       = azurerm_api_management_gateway.self_hosted.name
}

output "gateway_config_endpoint" {
  description = "Configuration endpoint for self-hosted gateway"
  value       = "${azurerm_api_management.apim.management_api_url}?api-version=2021-08-01"
}

output "subscription_primary_key" {
  description = "Test subscription API key"
  value       = azurerm_api_management_subscription.test.primary_key
  sensitive   = true
}

output "resource_group_name" {
  description = "Resource group name"
  value       = data.azurerm_resource_group.rg.name
}
