// Runtime configuration - overridden by Kubernetes ConfigMap in Phase 8+
// When deployed to AKS with security, this file is replaced via a ConfigMap mount
// with real Azure AD values. Without them, the app runs without authentication.
window.__CONFIG__ = {
  AZURE_CLIENT_ID: "",
  AZURE_TENANT_ID: ""
};
