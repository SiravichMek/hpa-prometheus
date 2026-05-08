# Verification Checklist

This document provides a step-by-step verification process to ensure everything works correctly.

## Pre-Setup Verification

### 1. Check Prerequisites
```bash
# Check Minikube
minikube version
# Expected: minikube version: v1.x.x or higher

# Check kubectl
kubectl version --client
# Expected: Client Version: v1.x.x

# Check Helm
helm version
# Expected: version.BuildInfo{Version:"v3.x.x"...}

# Check Podman
podman --version
# Expected: podman version 4.x.x or higher
```

### 2. Verify Minikube Status
```bash
minikube status
# Expected:
# minikube
# type: Control Plane
# host: Running
# kubelet: Running
# apiserver: Running
# kubeconfig: Configured
```

## Setup Script Verification

### 3. Run Setup Script
```bash
cd hpa-prometheus
chmod +x setup.sh
./setup.sh
```

**Expected Output:**
- ✓ All prerequisites are installed
- ✓ Minikube is running
- ✓ Metrics-server enabled
- ✓ Prometheus stack installed (or already installed)
- ✓ Prometheus Adapter installed
- ✓ Podman image built
- ✓ Image loaded into Minikube
- ✓ Application deployed
- ✓ HPA deployed

### 4. Verify Prometheus Stack
```bash
kubectl get pods -n monitoring
```

**Expected Pods (all Running):**
- prometheus-kube-prometheus-operator-xxx
- prometheus-prometheus-kube-prometheus-prometheus-0
- prometheus-grafana-xxx
- prometheus-kube-state-metrics-xxx
- prometheus-prometheus-node-exporter-xxx
- alertmanager-prometheus-kube-prometheus-alertmanager-0

### 5. Verify Prometheus Adapter
```bash
kubectl get pods -n monitoring | grep prometheus-adapter
kubectl get apiservice v1beta1.custom.metrics.k8s.io
```

**Expected:**
- prometheus-adapter pod: Running (1/1)
- APIService: Available

### 6. Verify Custom Metrics API
```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1
```

**Expected:** JSON output with list of available metrics (should be very long)

### 7. Verify Application Deployment
```bash
kubectl get pods -l app=demo-app
kubectl get svc demo-app
kubectl get servicemonitor demo-app
```

**Expected:**
- Pod: Running (1/1)
- Service: ClusterIP with port 5000
- ServiceMonitor: Created

### 8. Verify HPA
```bash
kubectl get hpa demo-app-hpa
kubectl describe hpa demo-app-hpa
```

**Expected HPA Status:**
```
NAME           REFERENCE             TARGETS                                    MINPODS   MAXPODS   REPLICAS   AGE
demo-app-hpa   Deployment/demo-app   cpu: X%/50%, memory: X%/80% + 2 more...   1         10        1          Xm
```

**Expected Metrics in describe:**
- resource cpu: X% / 50%
- resource memory: X% / 80%
- "http_requests_per_second": 0 / 10
- "http_active_requests": 0 / 5

### 9. Verify Prometheus is Scraping
```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &

# Check targets (open in browser)
# http://localhost:9090/targets
# Look for: serviceMonitor/default/demo-app/0 (should be UP)

# Query metrics (open in browser)
# http://localhost:9090/graph
# Query: http_requests_per_second
# Should show metric with value 0

# Kill port-forward
pkill -f "port-forward.*prometheus-kube-prometheus-prometheus"
```

## Application Access Verification

### 10. Test Application Endpoint
```bash
# Port-forward the application
kubectl port-forward svc/demo-app 8080:5000 &

# Test health endpoint
curl http://localhost:8080/health
# Expected: {"status":"healthy"}

# Test main endpoint
curl http://localhost:8080/
# Expected: HTML page with pod name and metrics

# Test metrics endpoint
curl http://localhost:8080/metrics
# Expected: Prometheus metrics in text format

# Kill port-forward
pkill -f "port-forward.*demo-app"
```

## Grafana Verification

### 11. Access Grafana
```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &

# Open browser: http://localhost:3000
# Login: admin / prom-operator
```

### 12. Import Dashboard
1. Click "+" icon → "Import"
2. Click "Upload JSON file"
3. Select `grafana/dashboard.json`
4. Click "Import"

**Expected:** Dashboard with 6 panels showing metrics

### 13. Verify Dashboard Data
- **Request Rate**: Should show 0 initially
- **Active Pods**: Should show 1
- **CPU Usage**: Should show low percentage
- **Memory Usage**: Should show low percentage
- **Active Requests**: Should show 0
- **Request Latency**: May show "No data"

## Load Test Verification

### 14. Run Load Test
```bash
chmod +x load-test/load-test.sh
./load-test/load-test.sh
```

**Expected Behavior:**
1. Port-forward starts automatically
2. Service connectivity test passes
3. Load test phases execute:
   - Phase 1: Warm-up (30s)
   - Phase 2: Ramp-up (60s)
   - Phase 3: Peak load (300s default)
   - Phase 4: Cool-down (60s)
4. Real-time monitoring shows:
   - HPA metrics increasing
   - Pod count increasing (up to 10)
   - Recent scaling events

### 15. Monitor Scaling in Real-Time
```bash
# In another terminal
kubectl get hpa demo-app-hpa -w
```

**Expected Scaling Behavior:**
- Initial: 1 replica
- After load starts: Metrics increase
- When any metric exceeds threshold:
  - CPU > 50%, OR
  - Memory > 80%, OR
  - http_requests_per_second > 10, OR
  - http_active_requests > 5
- Replicas increase (2, 3, 4... up to 10)
- After load stops: Replicas decrease after 60s stabilization

### 16. Verify Grafana During Load Test
Open Grafana dashboard during load test:

**Expected:**
- **Request Rate**: Increases to 50-100+ req/s
- **Active Pods**: Increases from 1 to multiple pods
- **CPU Usage**: Increases per pod
- **Memory Usage**: May increase slightly
- **Active Requests**: Shows concurrent requests
- **Request Latency**: Shows p50 and p95 latencies

## Post-Test Verification

### 17. Check Final State
```bash
# Wait for scale-down (60s after load stops)
kubectl get hpa demo-app-hpa
kubectl get pods -l app=demo-app

# Check events
kubectl get events --sort-by='.lastTimestamp' | grep -E "demo-app|Scaled" | tail -10
```

**Expected:**
- HPA shows metrics back to low values
- Pods scale back down to 1 (after stabilization window)
- Events show scaling up and down activities

### 18. Verify Custom Metrics
```bash
# Check specific metrics
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/http_requests_per_second" | jq .
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/http_active_requests" | jq .
```

**Expected:** JSON with metric values for each pod

## Troubleshooting Verification

### If HPA Shows `<unknown>` for Custom Metrics

```bash
# 1. Check Prometheus Adapter logs
kubectl logs -n monitoring deployment/prometheus-adapter --tail=50

# 2. Check if metrics exist in Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
# Open: http://localhost:9090/graph
# Query: http_requests_per_second{namespace="default"}

# 3. Verify ServiceMonitor
kubectl get servicemonitor demo-app -o yaml

# 4. Check Prometheus targets
# http://localhost:9090/targets
# Look for demo-app target (should be UP)

# 5. Restart Prometheus Adapter
kubectl rollout restart deployment/prometheus-adapter -n monitoring
kubectl rollout status deployment/prometheus-adapter -n monitoring
```

### If Pods Don't Scale

```bash
# 1. Check HPA status
kubectl describe hpa demo-app-hpa

# 2. Check HPA events
kubectl get events --field-selector involvedObject.name=demo-app-hpa

# 3. Verify metrics are above threshold
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/http_requests_per_second"

# 4. Check deployment
kubectl describe deployment demo-app

# 5. Check resource limits
kubectl get pods -l app=demo-app -o yaml | grep -A 5 resources
```

### If Load Test Fails

```bash
# 1. Check if port-forward is working
kubectl port-forward svc/demo-app 8080:5000 &
curl http://localhost:8080/health

# 2. Check pod logs
kubectl logs -l app=demo-app --tail=50

# 3. Check service
kubectl get svc demo-app
kubectl describe svc demo-app

# 4. Check endpoints
kubectl get endpoints demo-app
```

## Success Criteria

✅ **All checks should pass:**

1. All prerequisites installed
2. Minikube running with Docker driver
3. Prometheus stack deployed and running
4. Prometheus Adapter deployed and serving custom metrics
5. Application deployed and accessible
6. HPA configured with 4 metrics (CPU, Memory, 2 custom)
7. Custom metrics API returns data
8. Prometheus scraping application metrics
9. Grafana accessible and dashboard imported
10. Load test runs successfully
11. Pods scale up during load (1 → multiple)
12. Pods scale down after load stops (→ 1)
13. Grafana shows real-time metrics during load test
14. No errors in pod logs
15. No errors in Prometheus Adapter logs

## Cleanup Verification

```bash
# Remove all resources
kubectl delete -f k8s/

# Verify deletion
kubectl get pods -l app=demo-app
# Expected: No resources found

kubectl get hpa demo-app-hpa
# Expected: Error: horizontalpodautoscalers.autoscaling "demo-app-hpa" not found

# Optional: Remove Prometheus
helm uninstall prometheus -n monitoring
helm uninstall prometheus-adapter -n monitoring

# Optional: Stop Minikube
minikube stop
```

## Quick Health Check Command

Run this single command to check overall health:

```bash
echo "=== Pods ===" && \
kubectl get pods -l app=demo-app && \
echo -e "\n=== HPA ===" && \
kubectl get hpa demo-app-hpa && \
echo -e "\n=== Custom Metrics ===" && \
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/http_requests_per_second" 2>&1 | head -5 && \
echo -e "\n=== Prometheus Adapter ===" && \
kubectl get pods -n monitoring | grep prometheus-adapter
```

**Expected:** All commands succeed with appropriate output

---

**Note:** If any verification step fails, refer to the troubleshooting section in QUICKSTART.md or the specific troubleshooting commands above.