# Phase 6: AKS Architecture

This document explains the architectural differences when deploying Dapr to Azure Kubernetes Service compared to local minikube.

## Azure Resources

### Resource Group
All Azure resources are contained in a single resource group for easy management and cleanup:

```
rg-dapr-demo/
├── acrdaprdemo{random}     # Azure Container Registry
├── aks-dapr-demo           # AKS Cluster
│   ├── MC_rg-dapr-demo_*   # Managed node resource group
│   │   ├── Virtual Machines (2x Standard_B2s)
│   │   ├── Managed Disks (OS + PVCs)
│   │   ├── Virtual Network
│   │   └── Public IP (for LoadBalancer)
```

### Azure Container Registry (ACR)

ACR stores Docker images that AKS pulls during deployment:

```
acrdaprdemo{random}.azurecr.io/
├── catalog-service:latest
├── order-service:latest
├── notification-service:latest
├── workflow-service:latest
└── web-app:latest
```

**ACR Tasks** builds images in the cloud, eliminating the need for local Docker:

```bash
# Instead of: docker build -t myimage . && docker push myimage
az acr build --registry $ACR_NAME --image myimage:latest .
```

### AKS-ACR Integration

When AKS is created with `--attach-acr`, Azure automatically:
1. Creates a managed identity for AKS
2. Grants `AcrPull` role to the identity
3. Configures kubelet to authenticate with ACR

This means pods can pull images without explicit credentials.

## Image Pull Changes

### Minikube (Phase 3-5)
```yaml
# Uses local Docker daemon
image: catalog-service:latest
imagePullPolicy: Never  # Don't try to pull from registry
```

### AKS (Phase 6)
```yaml
# Pulls from ACR
image: {{ACR_LOGIN_SERVER}}/catalog-service:latest
imagePullPolicy: Always  # Always check for latest image
```

The `{{ACR_LOGIN_SERVER}}` placeholder is replaced at deploy time with the actual ACR hostname (e.g., `acrdaprdemo123.azurecr.io`).

## Public Access Pattern

### Minikube
```
User → localhost:8080 → port-forward → Service → Pod
```

Port-forward is required because minikube runs locally without external IP.

### AKS with LoadBalancer
```
User → dapr-demo.eastus.cloudapp.azure.com → Azure Load Balancer → Ingress Controller → Pod
```

The nginx-ingress controller is configured as a LoadBalancer service, which provisions an Azure Public IP with a DNS label.

### DNS Label Annotation
```yaml
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/azure-dns-label-name: "dapr-demo-{random}"
```

This creates a fully-qualified domain name:
```
dapr-demo-{random}.{region}.cloudapp.azure.com
```

## Persistent Storage

### Minikube
Minikube uses ephemeral storage by default. Data is lost when pods restart or the cluster is deleted.

### AKS with Azure Managed Disks
AKS provides the `managed-csi` storage class that provisions Azure Managed Disks:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-data
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: managed-csi  # Azure Managed Disk
  resources:
    requests:
      storage: 1Gi
```

**Benefits:**
- Data persists across pod restarts
- Automatic backup and snapshot capabilities
- Scalable from 1GB to 32TB

**Cost:** ~$0.05/GB/month for Standard SSD

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Azure AKS Cluster                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    dapr-demo namespace                      │ │
│  │                                                             │ │
│  │  ┌─────────────────┐                                        │ │
│  │  │  LoadBalancer   │ ←── Public IP: x.x.x.x                │ │
│  │  │  (nginx-ingress)│     DNS: dapr-demo.eastus...          │ │
│  │  │  + Dapr sidecar │                                        │ │
│  │  └────────┬────────┘                                        │ │
│  │           │                                                  │ │
│  │           ▼                                                  │ │
│  │  ┌────────────────────────────────────────────────────────┐ │ │
│  │  │                  Ingress Rules                          │ │ │
│  │  │  /v1.0/* → api-gateway-dapr (Dapr sidecar)             │ │ │
│  │  │  /*      → web-app                                      │ │ │
│  │  └────────────────────────────────────────────────────────┘ │ │
│  │                                                             │ │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌──────────┐ │ │
│  │  │ catalog-  │  │  order-   │  │ notifica- │  │ workflow │ │ │
│  │  │ service   │  │  service  │  │   tion    │  │ -service │ │ │
│  │  │ + daprd   │  │ + daprd   │  │ + daprd   │  │ + daprd  │ │ │
│  │  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘  └────┬─────┘ │ │
│  │        │              │              │              │       │ │
│  │        └──────────────┴──────────────┴──────────────┘       │ │
│  │                    Dapr Service Mesh                        │ │
│  │                                                             │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │ │
│  │  │    Redis    │  │   Zipkin    │  │ web-app (no sidecar)│ │ │
│  │  │ + Azure Disk│  │ + Azure Disk│  │                     │ │ │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘ │ │
│  │                                                             │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    dapr-system namespace                    │ │
│  │  dapr-operator | dapr-sentry | dapr-sidecar-injector | ... │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Configuration Management

### .azure-config File
The setup script generates a configuration file with Azure resource details:

```bash
# .azure-config (generated, gitignored)
RESOURCE_GROUP="rg-dapr-demo"
LOCATION="eastus"
ACR_NAME="acrdaprdemo12345"
ACR_LOGIN_SERVER="acrdaprdemo12345.azurecr.io"
AKS_NAME="aks-dapr-demo"
DNS_LABEL="dapr-demo-12345"
EXTERNAL_IP="20.85.xxx.xxx"
```

Other scripts source this file to get the configuration:
```bash
source "$SCRIPT_DIR/../.azure-config"
```

### Manifest Substitution
Service manifests use a placeholder that's replaced at deploy time:

```yaml
# In manifest:
image: {{ACR_LOGIN_SERVER}}/catalog-service:latest

# After substitution:
image: acrdaprdemo12345.azurecr.io/catalog-service:latest
```

The `deploy-all.sh` script handles this:
```bash
sed "s|{{ACR_LOGIN_SERVER}}|$ACR_LOGIN_SERVER|g" "$file" | kubectl apply -f -
```

## Security Considerations

### Current Setup (Demo)
- Public endpoint without authentication
- No HTTPS (HTTP only)
- No network policies
- Redis without password

### Production Recommendations
1. **Enable HTTPS**: Use cert-manager with Let's Encrypt
2. **API Authentication**: Add Azure AD or API keys
3. **Network Policies**: Restrict pod-to-pod communication
4. **Managed Services**: Use Azure Redis Cache, Azure Service Bus
5. **Secrets Management**: Use Azure Key Vault (Phase 7)
6. **Private Endpoints**: Keep services internal where possible

## Cost Optimization

### Right-sizing Nodes
The demo uses `Standard_B2s` (burstable VMs) which are cost-effective for development:
- 2 vCPUs, 4GB RAM
- ~$30/month per node

For production, consider:
- Reserved instances (up to 72% savings)
- Spot instances for non-critical workloads
- Autoscaling based on load

### Storage Optimization
- Use `Standard_LRS` for non-critical data (cheaper than Premium)
- Set appropriate disk sizes (charged per provisioned GB)
- Consider Azure Files for shared storage needs

### Cleanup Automation
Set up Azure Automation to delete resources on a schedule:
```bash
# Delete cluster nightly (for dev environments)
az aks stop --resource-group rg-dapr-demo --name aks-dapr-demo

# Restart in the morning
az aks start --resource-group rg-dapr-demo --name aks-dapr-demo
```

Stopping the cluster (instead of deleting) preserves configuration while avoiding compute charges.
