# Kubernetes Auto-Scaling Demo with Prometheus and Grafana

This project demonstrates Kubernetes Horizontal Pod Autoscaling (HPA) using custom Prometheus metrics, with visualization in Grafana and load testing capabilities.

## Prerequisites

- Minikube installed and running
- Helm 3 installed
- kubectl configured
- Podman installed
- Prometheus installed via Helm (as mentioned)

## Project Structure

```
k8s-auto-scaler/
├── app/                          # Sample application
│   ├── app.py                    # Flask app with metrics
│   ├── requirements.txt          # Python dependencies
│   └── Dockerfile               # Container image
├── k8s/                         # Kubernetes manifests
│   ├── deployment.yaml          # Application deployment
│   ├── service.yaml             # Service definition
│   ├── servicemonitor.yaml      # Prometheus ServiceMonitor
│   └── hpa.yaml                 # HPA configuration
├── grafana/                     # Grafana configuration
│   └── dashboard.json           # Pre-configured dashboard
├── load-test/                   # Load testing
│   └── load-test.sh            # Load testing script
└── setup.sh                     # Setup script

```

## Quick Start

1. **Start Minikube with sufficient resources:**
   ```bash
   minikube start --cpus=4 --memory=8192 --driver=docker
   ```

2. **Enable metrics-server:**
   ```bash
   minikube addons enable metrics-server
   ```

3. **Run the setup script:**
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

4. **Access Grafana:**
   ```bash
   kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
   ```
   Open http://localhost:3000 (default credentials: admin/prom-operator)
   
   **For detailed Grafana setup and dashboard usage, see [GRAFANA_SETUP.md](GRAFANA_SETUP.md)**

5. **Run load test:**
   ```bash
   chmod +x load-test/load-test.sh
   ./load-test/load-test.sh
   ```

## Components

### Sample Application
- Flask-based Python application
- Exposes `/metrics` endpoint for Prometheus
- Custom metrics:
  - `http_requests_per_second`: Rate of incoming requests
  - `http_active_requests`: Number of concurrent requests
  - `http_requests_total`: Total request counter
- Simulates CPU-intensive work on `/load` endpoint

### Prometheus Integration
- ServiceMonitor for automatic scraping
- Custom metrics collection
- Integration with Prometheus Adapter

### HPA Configuration
- Scales based on multiple metrics:
  - CPU utilization: 50%
  - Memory utilization: 80%
  - Custom Prometheus metric `http_requests_per_second`: 10 req/s per pod
  - Custom Prometheus metric `http_active_requests`: 5 concurrent requests per pod
- Min replicas: 1
- Max replicas: 10
- Scale-up: Immediate (0s stabilization)
- Scale-down: 60s stabilization window

### Grafana Dashboard
- Pre-configured dashboard with 6 panels:
  1. **Request Rate** - Total and per-pod request rates
  2. **Active Pods** - Gauge showing current pod count
  3. **CPU Usage** - CPU consumption per pod
  4. **Memory Usage** - Memory consumption per pod
  5. **Active Requests** - Concurrent requests being processed
  6. **Request Latency** - p50 and p95 latency percentiles
- Real-time auto-refresh capability
- Import from `grafana/dashboard.json`
- See [GRAFANA_SETUP.md](GRAFANA_SETUP.md) for detailed instructions

## Monitoring the Demo

Watch pods scaling:
```bash
kubectl get hpa -w
kubectl get pods -w
```

View application logs:
```bash
kubectl logs -f deployment/demo-app
```

Check metrics:
```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1
```

## Cleanup

```bash
kubectl delete -f k8s/
minikube stop
```

## Troubleshooting

1. **HPA shows `<unknown>` for metrics:**
   - Wait 2-3 minutes for metrics to populate
   - Check Prometheus Adapter logs: `kubectl logs -n monitoring deployment/prometheus-adapter`

2. **Pods not scaling:**
   - Verify ServiceMonitor is scraping: Check Prometheus targets
   - Ensure metrics are being exposed: `curl http://<pod-ip>:5000/metrics`

3. **Grafana cannot connect to Prometheus:**
   - Run the fix script: `./fix-grafana-datasource.sh`
   - Or manually configure data source (see GRAFANA_SETUP.md)

4. **Grafana dashboard not showing data:**
   - Verify Prometheus data source is configured and working
   - Check that pods are labeled correctly for scraping
   - See GRAFANA_SETUP.md for detailed troubleshooting