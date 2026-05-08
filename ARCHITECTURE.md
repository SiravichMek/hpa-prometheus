# Architecture Overview

This document explains the architecture and components of the Kubernetes auto-scaling demo.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Minikube Cluster                         │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Default Namespace                        │ │
│  │                                                              │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │ │
│  │  │   Pod 1      │  │   Pod 2      │  │   Pod N      │     │ │
│  │  │  demo-app    │  │  demo-app    │  │  demo-app    │     │ │
│  │  │  :5000       │  │  :5000       │  │  :5000       │     │ │
│  │  │  /metrics    │  │  /metrics    │  │  /metrics    │     │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │ │
│  │         │                  │                  │             │ │
│  │         └──────────────────┴──────────────────┘             │ │
│  │                            │                                │ │
│  │                    ┌───────▼────────┐                       │ │
│  │                    │   Service      │                       │ │
│  │                    │   demo-app     │                       │ │
│  │                    │   NodePort     │                       │ │
│  │                    └───────┬────────┘                       │ │
│  │                            │                                │ │
│  │                    ┌───────▼────────┐                       │ │
│  │                    │      HPA       │                       │ │
│  │                    │  demo-app-hpa  │                       │ │
│  │                    └───────┬────────┘                       │ │
│  └────────────────────────────┼────────────────────────────────┘ │
│                                │                                  │
│  ┌────────────────────────────┼────────────────────────────────┐ │
│  │              Monitoring Namespace                           │ │
│  │                            │                                │ │
│  │  ┌─────────────────────────▼──────────────────────────┐    │ │
│  │  │              Prometheus Operator                    │    │ │
│  │  │  ┌──────────────┐  ┌──────────────┐               │    │ │
│  │  │  │ Prometheus   │  │  Grafana     │               │    │ │
│  │  │  │   :9090      │  │   :3000      │               │    │ │
│  │  │  └──────┬───────┘  └──────────────┘               │    │ │
│  │  │         │                                           │    │ │
│  │  │  ┌──────▼───────────────────────┐                 │    │ │
│  │  │  │   ServiceMonitor             │                 │    │ │
│  │  │  │   (Scrapes /metrics)         │                 │    │ │
│  │  │  └──────────────────────────────┘                 │    │ │
│  │  └──────────────────┬───────────────────────────────┘    │ │
│  │                     │                                     │ │
│  │  ┌──────────────────▼───────────────────────────────┐    │ │
│  │  │         Prometheus Adapter                        │    │ │
│  │  │  (Exposes custom metrics to K8s API)             │    │ │
│  │  └──────────────────┬───────────────────────────────┘    │ │
│  │                     │                                     │ │
│  └─────────────────────┼─────────────────────────────────────┘ │
│                        │                                       │
│  ┌─────────────────────▼─────────────────────────────────┐    │
│  │         Kubernetes Metrics API                        │    │
│  │  /apis/custom.metrics.k8s.io/v1beta1                 │    │
│  └───────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Demo Application (Flask)

**Location:** `app/app.py`

**Purpose:** Sample web application that exposes Prometheus metrics

**Key Features:**
- HTTP endpoints: `/`, `/health`, `/load`, `/metrics`
- Exposes custom metrics via Prometheus client library
- Simulates CPU-intensive work to trigger scaling

**Metrics Exposed:**
- `http_requests_total`: Counter of total HTTP requests
- `http_requests_per_second`: Gauge of current request rate
- `http_active_requests`: Gauge of concurrent requests
- `http_request_duration_seconds`: Histogram of request latency

**Container Image:** Built locally in Minikube using `demo-app:latest`

### 2. Kubernetes Deployment

**Location:** `k8s/deployment.yaml`

**Configuration:**
- Initial replicas: 1
- Resource requests: 100m CPU, 128Mi memory
- Resource limits: 500m CPU, 256Mi memory
- Health checks: Liveness and readiness probes on `/health`
- Annotations for Prometheus scraping

### 3. Kubernetes Service

**Location:** `k8s/service.yaml`

**Type:** NodePort

**Purpose:** Exposes the application and enables load balancing across pods

### 4. ServiceMonitor

**Location:** `k8s/servicemonitor.yaml`

**Purpose:** Tells Prometheus Operator to scrape metrics from the application

**Configuration:**
- Scrape interval: 15 seconds
- Scrape timeout: 10 seconds
- Target: `/metrics` endpoint on port 5000

### 5. Horizontal Pod Autoscaler (HPA)

**Location:** `k8s/hpa.yaml`

**API Version:** autoscaling/v2

**Scaling Configuration:**
- Min replicas: 1
- Max replicas: 10

**Metrics:**

1. **CPU Utilization** (Resource metric)
   - Target: 50% average utilization
   - Built-in Kubernetes metric

2. **Custom Metric: http_requests_per_second** (Pods metric)
   - Target: 100 requests/second per pod
   - Sourced from Prometheus via Prometheus Adapter

**Scaling Behavior:**

*Scale Up:*
- No stabilization window (immediate)
- Can scale up by 100% or add 2 pods per 30 seconds
- Uses the maximum of the two policies

*Scale Down:*
- Stabilization window: 60 seconds
- Can scale down by 50% per 60 seconds
- Prevents rapid scale-down (flapping)

### 6. Prometheus Stack

**Installation:** Via Helm chart `kube-prometheus-stack`

**Components:**
- **Prometheus:** Metrics collection and storage
- **Grafana:** Metrics visualization
- **Alertmanager:** Alert management (not used in this demo)
- **Prometheus Operator:** Manages Prometheus instances

**Configuration:**
- ServiceMonitor selector: Accepts all ServiceMonitors
- PodMonitor selector: Accepts all PodMonitors

### 7. Prometheus Adapter

**Location:** `k8s/prometheus-adapter-values.yaml`

**Purpose:** Bridges Prometheus metrics to Kubernetes Custom Metrics API

**Custom Rules:**

1. **http_requests_per_second**
   - Direct mapping from Prometheus gauge
   - Used by HPA for scaling decisions

2. **http_requests_per_second** (from rate)
   - Calculated from `http_requests_total` counter
   - Uses 2-minute rate calculation

3. **http_active_requests**
   - Direct mapping for monitoring concurrent requests

**Resource Rules:**
- CPU and memory metrics for standard resource-based scaling

### 8. Grafana Dashboard

**Location:** `grafana/dashboard.json`

**Panels:**

1. **Request Rate**
   - Total requests per second across all pods
   - Average requests per second per pod

2. **Active Pods**
   - Gauge showing current number of running pods
   - Color-coded thresholds (green < 5, yellow < 8, red >= 8)

3. **CPU Usage by Pod**
   - Time series of CPU utilization per pod
   - Helps correlate CPU with scaling events

4. **Memory Usage by Pod**
   - Time series of memory consumption per pod

5. **Active Requests by Pod**
   - Shows concurrent request handling per pod

6. **Request Latency (p50, p95)**
   - Percentile latency metrics
   - Helps identify performance degradation

**Refresh Rate:** 5 seconds

### 9. Load Testing Script

**Location:** `load-test/load-test.sh`

**Phases:**

1. **Warm-up (30s):** Light load to initialize metrics
2. **Ramp-up (60s):** Gradually increase load
3. **Peak Load (configurable):** Sustained high load to trigger scaling
4. **Cool-down (60s):** Stop traffic to observe scale-down

**Features:**
- Real-time monitoring of HPA and pods
- Configurable duration, concurrent users, and requests
- Mix of endpoints (normal and heavy load)
- Automatic cleanup

## Data Flow

### Metrics Collection Flow

```
Application Pod
    │
    │ Exposes /metrics endpoint
    │
    ▼
ServiceMonitor (CRD)
    │
    │ Configures scraping
    │
    ▼
Prometheus
    │
    │ Stores time-series data
    │
    ▼
Prometheus Adapter
    │
    │ Transforms to K8s metrics
    │
    ▼
Custom Metrics API
    │
    │ /apis/custom.metrics.k8s.io/v1beta1
    │
    ▼
HPA Controller
    │
    │ Reads metrics and makes scaling decisions
    │
    ▼
Deployment
    │
    │ Adjusts replica count
    │
    ▼
Pods scaled up/down
```

### Scaling Decision Flow

```
1. HPA queries metrics every 15 seconds (default)
   ├─ CPU utilization from metrics-server
   └─ Custom metrics from Prometheus Adapter

2. HPA calculates desired replicas
   Formula: desiredReplicas = ceil[currentReplicas * (currentMetricValue / targetMetricValue)]

3. HPA applies scaling policies
   ├─ Check min/max replica constraints
   ├─ Apply stabilization windows
   └─ Apply rate limits (scale-up/down policies)

4. HPA updates Deployment
   └─ Deployment controller creates/deletes pods

5. Pods start/terminate
   ├─ New pods: Pull image → Start container → Pass readiness probe
   └─ Terminating pods: Receive SIGTERM → Graceful shutdown → Removed from service
```

## Metric Calculation Examples

### CPU-based Scaling

```
Current: 3 pods, average 75% CPU utilization
Target: 50% CPU utilization

Desired replicas = ceil[3 * (75 / 50)] = ceil[4.5] = 5 pods
```

### Custom Metric Scaling

```
Current: 2 pods, 250 requests/second total (125 req/s per pod)
Target: 100 requests/second per pod

Desired replicas = ceil[2 * (125 / 100)] = ceil[2.5] = 3 pods
```

## Key Design Decisions

### Why Prometheus Adapter?

- Enables HPA to use custom Prometheus metrics
- Provides flexibility beyond CPU/memory metrics
- Allows business-logic-based scaling (e.g., request rate, queue depth)

### Why ServiceMonitor?

- Declarative configuration for Prometheus scraping
- Automatic discovery of targets
- Integrates with Prometheus Operator

### Why Multiple Metrics in HPA?

- CPU: Protects against resource exhaustion
- Request rate: Scales based on actual load
- HPA uses the metric that requires the most replicas

### Scaling Behavior Configuration

- **Fast scale-up:** Respond quickly to traffic spikes
- **Slow scale-down:** Prevent flapping and maintain stability
- **Stabilization window:** Avoid rapid scaling oscillations

## Performance Considerations

### Resource Requests/Limits

- **Requests:** Guaranteed resources for scheduling
- **Limits:** Maximum resources to prevent resource hogging
- Properly sized to allow scaling without node exhaustion

### Metric Collection Overhead

- Scrape interval: 15 seconds (balance between freshness and overhead)
- Metric cardinality: Limited to essential metrics
- Retention: Prometheus default (15 days)

### HPA Evaluation Frequency

- Default: Every 15 seconds
- Can be adjusted via `--horizontal-pod-autoscaler-sync-period` flag
- Trade-off between responsiveness and API server load

## Security Considerations

### Network Policies

- Not implemented in this demo (for simplicity)
- Production: Restrict traffic between namespaces

### RBAC

- Prometheus Operator creates necessary ServiceAccounts
- HPA controller uses built-in permissions

### Secrets Management

- Grafana credentials: Stored in Kubernetes secrets
- Production: Use external secret management (e.g., Vault)

## Monitoring and Observability

### What to Monitor

1. **HPA Status:** `kubectl get hpa -w`
2. **Pod Status:** `kubectl get pods -w`
3. **Events:** `kubectl get events --sort-by='.lastTimestamp'`
4. **Metrics:** Grafana dashboard
5. **Logs:** `kubectl logs -l app=demo-app`

### Key Metrics

- Request rate (total and per pod)
- CPU/Memory utilization
- Pod count
- Request latency
- Active requests

## Troubleshooting Guide

### Common Issues

1. **HPA shows `<unknown>`**
   - Metrics not available yet (wait 2-3 minutes)
   - Prometheus Adapter not configured correctly
   - ServiceMonitor not scraping

2. **Pods not scaling**
   - Metrics below threshold
   - HPA policies preventing scaling
   - Resource constraints on nodes

3. **Slow scaling**
   - Stabilization windows
   - Image pull time for new pods
   - Readiness probe delays

## Future Enhancements

Potential improvements for production use:

1. **Multiple Metrics:** Add queue depth, error rate
2. **Predictive Scaling:** Use ML for traffic prediction
3. **Vertical Pod Autoscaler:** Optimize resource requests
4. **Cluster Autoscaler:** Scale nodes based on demand
5. **Custom Metrics:** Business-specific KPIs
6. **Alerting:** Prometheus Alertmanager rules
7. **Network Policies:** Secure pod-to-pod communication
8. **Pod Disruption Budgets:** Ensure availability during scaling