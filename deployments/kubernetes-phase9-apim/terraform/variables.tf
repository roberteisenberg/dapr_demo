variable "resource_group_name" {
  description = "Existing resource group from Phase 6/8 AKS deployment"
  type        = string
  default     = "rg-dapr-demo"
}

variable "location" {
  description = "Azure region (must match AKS cluster)"
  type        = string
  default     = "eastus"
}

variable "apim_name" {
  description = "API Management instance name (must be globally unique)"
  type        = string
  default     = "dapr-demo-apim"
}

variable "apim_publisher_name" {
  description = "APIM publisher name"
  type        = string
  default     = "Dapr Demo"
}

variable "apim_publisher_email" {
  description = "APIM publisher email (required)"
  type        = string
}

variable "gateway_name" {
  description = "Self-hosted gateway name"
  type        = string
  default     = "aks-gateway"
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default = {
    project = "dapr-demo"
    phase   = "9-apim"
  }
}
