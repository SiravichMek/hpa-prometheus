# Quick Start Guide

This guide will help you get the auto-scaling demo up and running in minutes.

## Prerequisites

Ensure you have the following installed:
- Minikube (running)
- kubectl
- Helm 3
- Podman

## Step-by-Step Setup

### 1. Clone and Navigate to Project

```bash
cd /Users/siravich/Desktop/k8s-auto-scaler
```

### 2. Run the Setup Script

```bash
chmod +x setup.sh
./setup.sh
```

This script will:
- ✅ Check prerequisites
- ✅ Start Minikube with Podman driver (if not running)
- ✅ Enable metrics-server
- ✅ Install Prometheus stack (if not installed)
- ✅ Install Prometheus Adapter
- ✅ Build the demo application Podman image (hpa-demo-app:latest)
- ✅ Deploy the application
- ✅ Configure HPA (Horizontal Pod Autoscaler)

**Note:** The setup takes about 5-10 minutes depending on your internet connection.

### 3. Verify Installation

Check that everything is running:

```bash
# Check pods
kubectl get pods -l app=demo-app

# Check HPA
kubectl get hpa demo-app-hpa

# Check service
kubectl get svc demo-app
```

### 4. Access the Application

Port-forward the application service (in a new terminal):

```bash
kubectl port-forward svc/demo-app 8080:5000
```

Then open http://localhost:8080 in your browser to see the demo application.

**Note:** With Docker driver, we use port-forwarding instead of NodePort for service access.

### 5. Access Grafana Dashboard

In a new terminal, port-forward Grafana:

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

Then open http://localhost:3000 in your browser.

**Default Credentials:**
- Username: `admin`
- Password: `prom-operator`

**Import the Dashboard:**
1. Click on "+" icon → "Import"
2. Click "Upload JSON file"
3. Select `grafana/dashboard.json`
4. Click "Import"

> **📖 For detailed Grafana setup, dashboard features, and troubleshooting, see [GRAFANA_SETUP.md](GRAFANA_SETUP.md)**

### 6. Run Load Test

In a new terminal, run the load test:

```bash
chmod +x load-test/load-test.sh
./load-test/load-test.sh
```

**Optional Parameters:**
```bash
# Custom duration (seconds), concurrent users, requests per user
./load-test/load-test.sh 600 100 2000
```

### 7. Monitor Auto-Scaling

Watch the HPA in action:

```bash
# Watch HPA status
kubectl get hpa demo-app-hpa -w

# Watch pods scaling
kubectl get pods -l app=demo-app -w
```

## What to Observe

### In Terminal

You'll see:
- **HPA metrics**: Current CPU usage and custom metrics (requests/sec)
- **Replica count**: Pods scaling from 1 to up to 10
- **Events**: Scaling events as they happen

### In Grafana Dashboard

You'll see real-time graphs showing:
- 📊 **Request Rate**: Total and per-pod request rates
- 🎯 **Active Pods**: Gauge showing current pod count
- 💻 **CPU Usage**: CPU consumption per pod
- 💾 **Memory Usage**: Memory consumption per pod
- ⚡ **Active Requests**: Concurrent requests being processed
- ⏱️ **Request Latency**: p50 and p95 latency percentiles

## Understanding the Scaling Behavior

### Scale-Up Triggers

The HPA will scale up when ANY of these conditions are met:
1. **CPU utilization** exceeds 50%
2. **Memory utilization** exceeds 80%
3. **http_requests_per_second** exceeds 10 requests/second per pod
4. **http_active_requests** exceeds 5 concurrent requests per pod

### Scale-Down Behavior

- **Stabilization window**: 60 seconds (prevents flapping)
- **Scale-down rate**: Maximum 50% of pods per minute
- Pods will scale down when ALL metrics drop below their thresholds

## Testing Different Scenarios

### Light Load (No Scaling)
```bash
# Port-forward first (in another terminal): kubectl port-forward svc/demo-app 8080:5000
# Then send occasional requests
while true; do curl http://localhost:8080; sleep 2; done
```

### Medium Load (2-3 Pods)
```bash
# Run with fewer concurrent users
./load-test/load-test.sh 300 20 500
```

### Heavy Load (5-10 Pods)
```bash
# Run with more concurrent users
./load-test/load-test.sh 600 100 2000
```

## Troubleshooting

### HPA Shows `<unknown>` for Metrics

**Cause:** Metrics not yet available from Prometheus Adapter

**Solution:** Wait 2-3 minutes for metrics to populate, then check:

```bash
# Check if custom metrics are available
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1

# Check Prometheus Adapter logs
kubectl logs -n monitoring deployment/prometheus-adapter
```

### Pods Not Scaling

**Check ServiceMonitor:**
```bash
kubectl get servicemonitor demo-app -o yaml
```

**Check Prometheus Targets:**
```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Open http://localhost:9090/targets
# Look for demo-app targets
```

**Check Pod Metrics:**
```bash
# Get a pod name
POD_NAME=$(kubectl get pods -l app=demo-app -o jsonpath='{.items[0].metadata.name}')

# Check if metrics endpoint works
kubectl port-forward $POD_NAME 5000:5000

# In another terminal
curl http://localhost:5000/metrics
```

### Application Not Accessible

**Check pod status:**
```bash
kubectl get pods -l app=demo-app
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

**Check service:**
```bash
kubectl get svc demo-app
kubectl describe svc demo-app
```

## Cleanup

To remove all resources:

```bash
# Delete application resources
kubectl delete -f k8s/

# Optional: Delete Prometheus (if you want to start fresh)
helm uninstall prometheus -n monitoring
helm uninstall prometheus-adapter -n monitoring

# Optional: Stop Minikube
minikube stop
```

## Next Steps

- Experiment with different HPA configurations in `k8s/hpa.yaml`
- Modify the application to add more metrics in `app/app.py`
- Create custom Grafana dashboards
- Try different load patterns in the load test script

## Useful Commands

```bash
# View all custom metrics
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq .

# View specific metric for pods
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/http_requests_per_second" | jq .

# Check HPA details
kubectl describe hpa demo-app-hpa

# View recent events
kubectl get events --sort-by='.lastTimestamp' | grep -E "demo-app|Scaled"

# Check Prometheus Adapter configuration
kubectl get cm -n monitoring prometheus-adapter -o yaml
```

## Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review logs: `kubectl logs -l app=demo-app`
3. Check HPA status: `kubectl describe hpa demo-app-hpa`
4. Verify metrics: `kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1`

Happy scaling! 🚀