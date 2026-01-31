# Phase 6: Azure Kubernetes Service (AKS)

Deploy the Dapr microservices demo to **Azure Kubernetes Service (AKS)** with images on Docker Hub. Infrastructure provisioned with **Terraform** for reproducible, production-ready deployments.

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed explanations of Azure resources, ingress routing, and public access patterns.

## What's New in Phase 6?

| Feature | Description |
|---------|-------------|
| Terraform IaC | Infrastructure as Code for Azure resources |
| Azure AKS | Managed Kubernetes cluster in Azure |
| Docker Hub | Container images on Docker Hub (`reisenberg100/dapr-*`) |
| Public Access | No port-forward needed - public URL via Azure DNS label |
| Persistent Storage | Azure Managed Disks for Redis, MongoDB, RabbitMQ |
| Status Panel | Real-time activity drawer showing all Dapr operations |

## Screenshots

### Product Catalog
![Product Catalog](docs/react-form-fresh.png)

### Status Panel - Activity Log (Phase 3+)
Shows all Dapr service invocations with timestamps, response times, and HTTP status codes. Automatically captures every API call via Axios interceptors.

![Activity Log](docs/react-form-sidebbar-fresh.png)

For Quick Order screenshots, see [Phase 3 (Kubernetes)](../kubernetes/README.md#screenshots). For saga workflow screenshots, see [Phase 5 (Workflow)](../kubernetes-phase5-workflow/README.md#screenshots).

## What You'll Learn

- Terraform for Azure infrastructure provisioning
- AKS cluster creation and configuration
- Dapr on AKS with public access
- Cloud-native deployment patterns
- Frontend status panel with Axios interceptors for observability

## Prerequisites

- Azure subscription (free trial works)
- Azure CLI: `curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash`
- Terraform: `https://developer.hashicorp.com/terraform/install`
- kubectl
- Helm
- Dapr CLI
- Docker Desktop (for building images)
- jq (for test scripts): `sudo apt-get install -y jq`

## Quick Start

### 1. Provision Azure infrastructure with Terraform

```bash
cd deployments/kubernetes-phase6-aks/terraform

# Initialize Terraform
terraform init

# Preview what will be created
terraform plan

# Create resources (takes ~10-15 minutes)
terraform apply
```

This creates:
- Resource Group (`rg-dapr-demo`)
- AKS cluster with 2 nodes (`aks-dapr-demo`)

### 2. Configure cluster (install Dapr, nginx-ingress)

```bash
cd ..
./scripts/setup-cluster.sh
```

This:
- Configures kubectl for the AKS cluster
- Installs Dapr on Kubernetes
- Creates the dapr-demo namespace
- Installs nginx-ingress with Dapr sidecar and public IP

### 3. Build and push images

```bash
./scripts/build-and-push.sh --with-frontend
```

Builds images locally with Docker and pushes to Docker Hub (`reisenberg100/dapr-*`).

### 4. Deploy services

```bash
./scripts/deploy-all.sh --with-frontend
```

### 5. Access the application

After deployment, the script displays your public URL:

```
http://dapr-demo-{random}.eastus.cloudapp.azure.com
```

**No port-forward needed!** The application is publicly accessible.

**Test the deployment:**
```bash
./scripts/test-services.sh
./scripts/test-workflow.sh
```

## Status Panel (Phase 6.5)

The React frontend includes a real-time activity panel that shows all Dapr operations as they happen. Click the purple button in the bottom-right corner to open it.

**How it works:**
- Axios interceptors automatically capture every HTTP request to the Dapr sidecar
- Parses `/v1.0/invoke/{serviceId}/method/{path}` URLs to extract service name and method
- Logs request/response/error with timestamps and duration (ms)
- Groups consecutive workflow polling calls to reduce noise

**Two tabs:**
- **Activity** - Scrollable log of all Dapr calls, color-coded (blue=request, green=response, red=error)
- **Services** - Detected services with request counts and health derived from log history

**Backward compatible:** Works across all phases (3-6). If workflow-service is unavailable (Phase 3-4), the health check error is logged gracefully.

## Terraform Configuration

### Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `resource_group_name` | `rg-dapr-demo` | Resource group name |
| `location` | `eastus` | Azure region |
| `aks_cluster_name` | `aks-dapr-demo` | AKS cluster name |
| `node_count` | `2` | Number of worker nodes |
| `node_vm_size` | `standard_dc2ads_v5` | VM size for nodes (confidential computing) |

Override defaults:
```bash
terraform apply -var="location=westus2" -var="node_count=3"
```

### Outputs

After `terraform apply`, view outputs:
```bash
terraform output
```

| Output | Description |
|--------|-------------|
| `aks_cluster_name` | Name of the AKS cluster |
| `kube_config_command` | Command to configure kubectl |

## Cost Estimate

| Resource | SKU | ~Monthly Cost |
|----------|-----|---------------|
| AKS (2 nodes) | standard_dc2ads_v5 | ~$140 |
| Managed Disks | 4x 1GB | ~$2 |
| Public IP | Static | ~$3 |
| **Total** | | **~$145/month** |

**Tip:** Run `terraform destroy` when not in use to avoid charges.

## Infrastructure Swaps

Same as previous phases - infrastructure swaps still work:

```bash
./scripts/deploy-all.sh --pubsub rabbitmq --with-frontend
./scripts/deploy-all.sh --statestore mongodb --with-frontend
```

## Dashboards

Internal services require port-forwarding:

| Dashboard | Command | URL |
|-----------|---------|-----|
| Zipkin | `kubectl port-forward -n dapr-demo svc/zipkin 9411:9411` | http://localhost:9411 |
| Dapr | `dapr dashboard -k -n dapr-demo -p 8081` | http://localhost:8081 |

## Useful Commands

```bash
# View Terraform state
cd terraform && terraform show

# View all pods
kubectl get pods -n dapr-demo

# View service logs
kubectl logs -f deployment/catalog-service -c catalog-service -n dapr-demo

# Get public URL from config
source .azure-config && echo "http://$DNS_LABEL.$LOCATION.cloudapp.azure.com"
```

## Project Structure

```
deployments/kubernetes-phase6-aks/
├── terraform/
│   ├── providers.tf          # Azure provider configuration
│   ├── variables.tf          # Input variables
│   ├── main.tf               # AKS + Resource Group
│   └── outputs.tf            # Output values
├── config/
│   └── ingress-values.yaml   # nginx-ingress with Dapr sidecar
├── manifests/
│   ├── 00-namespace.yaml
│   ├── 01-redis.yaml         # + PersistentVolumeClaim
│   ├── 02-rabbitmq.yaml      # + PersistentVolumeClaim
│   ├── 02-mongodb.yaml       # + PersistentVolumeClaim
│   ├── 03-components/
│   ├── 04-catalog-service.yaml
│   ├── 05-order-service.yaml
│   ├── 06-notification-service.yaml
│   ├── 07-workflow-service.yaml
│   ├── 08-web-app.yaml
│   ├── 09-ingress.yaml
│   └── 10-zipkin.yaml
├── scripts/
│   ├── setup-cluster.sh      # Post-Terraform: Dapr, nginx-ingress
│   ├── build-and-push.sh     # Build images, push to Docker Hub
│   ├── deploy-all.sh         # Deploy to AKS
│   ├── cleanup.sh            # terraform destroy wrapper
│   ├── test-services.sh
│   └── test-workflow.sh
├── docs/                     # Screenshots
├── .azure-config             # Generated config (gitignored)
├── README.md
└── ARCHITECTURE.md
```

## Troubleshooting

### Terraform errors
```bash
# Re-initialize if provider issues
terraform init -upgrade

# See detailed plan
terraform plan -out=tfplan
terraform show tfplan
```

### Pods stuck in ImagePullBackOff
```bash
# Verify image exists on Docker Hub
docker pull reisenberg100/dapr-catalog-service:latest
```

### kubectl pointing at wrong cluster
```bash
# Check current context
kubectl config current-context

# Switch to AKS
az aks get-credentials --resource-group rg-dapr-demo --name aks-dapr-demo

# WSL users: ensure KUBECONFIG points to Windows config
export KUBECONFIG=/mnt/c/Users/<username>/.kube/config
```

## Cleanup

**Done with the demo?** Destroy all Azure resources:

```bash
./scripts/cleanup.sh
```

Or directly with Terraform:
```bash
cd terraform
terraform destroy
```

This deletes the entire resource group and all resources.
