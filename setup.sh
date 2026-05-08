#!/bin/bash

# Setup Script for K8s Auto-Scaling Demo
# This script sets up the entire demo environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}K8s Auto-Scaling Demo Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

command -v minikube >/dev/null 2>&1 || { echo -e "${RED}Error: minikube is not installed${NC}"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}Error: kubectl is not installed${NC}"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}Error: helm is not installed${NC}"; exit 1; }
command -v podman >/dev/null 2>&1 || { echo -e "${RED}Error: podman is not installed${NC}"; exit 1; }

echo -e "${GREEN}✓ All prerequisites are installed${NC}"
echo ""

# Check if Minikube is running
echo -e "${YELLOW}Checking Minikube status...${NC}"
if ! minikube status >/dev/null 2>&1; then
    echo -e "${YELLOW}Minikube is not running. Starting Minikube...${NC}"
    minikube start --cpus=4 --memory=8192 --driver=podman
else
    echo -e "${GREEN}✓ Minikube is running${NC}"
fi
echo ""

# Enable metrics-server
echo -e "${YELLOW}Enabling metrics-server addon...${NC}"
minikube addons enable metrics-server
echo -e "${GREEN}✓ Metrics-server enabled${NC}"
echo ""

# Check if Prometheus is installed
echo -e "${YELLOW}Checking Prometheus installation...${NC}"
if ! kubectl get namespace monitoring >/dev/null 2>&1; then
    echo -e "${YELLOW}Prometheus not found. Installing Prometheus stack...${NC}"
    
    # Add Prometheus Helm repo
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Install Prometheus stack
    helm install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --wait
    
    echo -e "${GREEN}✓ Prometheus stack installed${NC}"
else
    echo -e "${GREEN}✓ Prometheus is already installed${NC}"
fi
echo ""

# Install Prometheus Adapter
echo -e "${YELLOW}Installing Prometheus Adapter...${NC}"

# Check if APIService exists from a previous installation
if kubectl get apiservice v1beta1.metrics.k8s.io >/dev/null 2>&1; then
    echo -e "${YELLOW}Found existing metrics APIService, checking ownership...${NC}"
    
    # Check if it's managed by Helm
    if ! kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null | grep -q "Helm"; then
        echo -e "${YELLOW}APIService not managed by Helm, deleting it...${NC}"
        kubectl delete apiservice v1beta1.metrics.k8s.io
        sleep 5
    fi
fi

if helm list -n monitoring | grep -q prometheus-adapter; then
    echo -e "${YELLOW}Prometheus Adapter already installed, upgrading...${NC}"
    helm upgrade prometheus-adapter prometheus-community/prometheus-adapter \
        -f k8s/prometheus-adapter-values.yaml \
        -n monitoring \
        --wait \
        --timeout 10m
else
    echo -e "${YELLOW}Installing Prometheus Adapter (this may take a few minutes)...${NC}"
    helm install prometheus-adapter prometheus-community/prometheus-adapter \
        -f k8s/prometheus-adapter-values.yaml \
        -n monitoring \
        --wait \
        --timeout 10m
fi

# Verify installation
echo -e "${YELLOW}Verifying Prometheus Adapter installation...${NC}"
if kubectl get deployment -n monitoring prometheus-adapter >/dev/null 2>&1; then
    kubectl wait --for=condition=available --timeout=300s deployment/prometheus-adapter -n monitoring || {
        echo -e "${RED}Warning: Prometheus Adapter deployment not ready yet${NC}"
        echo -e "${YELLOW}Checking pod status...${NC}"
        kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-adapter
        kubectl describe pods -n monitoring -l app.kubernetes.io/name=prometheus-adapter | tail -20
    }
fi

echo -e "${GREEN}✓ Prometheus Adapter installed${NC}"
echo ""

# Build Podman image and load into Minikube
echo -e "${YELLOW}Building application Podman image...${NC}"
podman build -t hpa-demo-app:latest ./app
echo -e "${GREEN}✓ Podman image built${NC}"
echo ""

echo -e "${YELLOW}Loading image into Minikube...${NC}"
podman save localhost/hpa-demo-app:latest | minikube image load -
echo -e "${GREEN}✓ Image loaded into Minikube${NC}"
echo ""

# Deploy application
echo -e "${YELLOW}Deploying application...${NC}"
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/servicemonitor.yaml

echo -e "${YELLOW}Waiting for deployment to be ready...${NC}"
kubectl wait --for=condition=available --timeout=120s deployment/demo-app
echo -e "${GREEN}✓ Application deployed${NC}"
echo ""

# Wait for metrics to be available
echo -e "${YELLOW}Waiting for metrics to be available (this may take 2-3 minutes)...${NC}"
sleep 30

# Deploy HPA
echo -e "${YELLOW}Deploying HPA...${NC}"
kubectl apply -f k8s/hpa.yaml
echo -e "${GREEN}✓ HPA deployed${NC}"
echo ""

# Wait for HPA to initialize
echo -e "${YELLOW}Waiting for HPA to initialize...${NC}"
sleep 10

# Import Grafana dashboard
echo -e "${YELLOW}Setting up Grafana dashboard...${NC}"
echo -e "${BLUE}To import the dashboard:${NC}"
echo -e "${BLUE}1. Port-forward Grafana: kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80${NC}"
echo -e "${BLUE}2. Open http://localhost:3000 (default: admin/prom-operator)${NC}"
echo -e "${BLUE}3. Go to Dashboards > Import${NC}"
echo -e "${BLUE}4. Upload grafana/dashboard.json${NC}"
echo ""

# Display status
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${YELLOW}Current Status:${NC}"
echo ""
echo -e "${BLUE}Pods:${NC}"
kubectl get pods -l app=demo-app
echo ""
echo -e "${BLUE}Service:${NC}"
kubectl get svc demo-app
echo ""
echo -e "${BLUE}HPA:${NC}"
kubectl get hpa demo-app-hpa
echo ""

# Get service URL
SERVICE_URL=$(minikube service demo-app --url)
echo -e "${GREEN}Application URL: ${SERVICE_URL}${NC}"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo -e "${BLUE}1. Access the application:${NC}"
echo -e "   ${SERVICE_URL}"
echo ""
echo -e "${BLUE}2. Access Grafana:${NC}"
echo -e "   kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
echo -e "   Then open: http://localhost:3000"
echo -e "   Default credentials: admin/prom-operator"
echo ""
echo -e "${BLUE}3. Run load test:${NC}"
echo -e "   chmod +x load-test/load-test.sh"
echo -e "   ./load-test/load-test.sh"
echo ""
echo -e "${BLUE}4. Monitor scaling:${NC}"
echo -e "   kubectl get hpa -w"
echo -e "   kubectl get pods -w"
echo ""
echo -e "${BLUE}5. Check custom metrics:${NC}"
echo -e "   kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1"
echo ""
echo -e "${GREEN}Happy auto-scaling! 🚀${NC}"

# Made with Bob
