output "apim_name" {
  description = "API Management instance name"
  value       = azurerm_api_management.apim.name
}

output "apim_gateway_url" {
  description = "APIM cloud gateway URL (public API endpoint)"
  value       = azurerm_api_management.apim.gateway_url
}

output "nginx_ingress_fqdn" {
  description = "nginx-ingress FQDN that APIM routes to"
  value       = var.nginx_ingress_fqdn
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
