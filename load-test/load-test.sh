#!/bin/bash

# Load Testing Script for K8s Auto-Scaling Demo
# This script generates HTTP traffic to trigger auto-scaling

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="default"
SERVICE_NAME="demo-app"
DURATION=${1:-300}  # Default 5 minutes
CONCURRENT_USERS=${2:-50}  # Default 50 concurrent users
REQUESTS_PER_USER=${3:-1000}  # Requests per user

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}K8s Auto-Scaling Load Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Duration: ${DURATION}s${NC}"
echo -e "${GREEN}Concurrent Users: ${CONCURRENT_USERS}${NC}"
echo -e "${GREEN}Requests per User: ${REQUESTS_PER_USER}${NC}"
echo ""

# Get service URL using port-forward
echo -e "${YELLOW}Setting up port-forward to service...${NC}"

# Kill any existing port-forward on port 8080
pkill -f "port-forward.*demo-app" 2>/dev/null || true
sleep 2

# Start port-forward in background
kubectl port-forward svc/$SERVICE_NAME 8080:5000 -n $NAMESPACE > /dev/null 2>&1 &
PORT_FORWARD_PID=$!
sleep 3

SERVICE_URL="http://localhost:8080"

echo -e "${GREEN}Service URL: $SERVICE_URL${NC}"
echo -e "${BLUE}(Using port-forward, PID: $PORT_FORWARD_PID)${NC}"
echo ""

# Check if service is accessible
echo -e "${YELLOW}Testing service connectivity...${NC}"
if curl -s -f "$SERVICE_URL/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Service is accessible${NC}"
else
    echo -e "${RED}✗ Service is not accessible${NC}"
    echo -e "${YELLOW}Port-forward may not be ready yet, waiting...${NC}"
    sleep 5
    if curl -s -f "$SERVICE_URL/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Service is now accessible${NC}"
    else
        echo -e "${RED}✗ Still cannot access service${NC}"
        kill $PORT_FORWARD_PID 2>/dev/null || true
        exit 1
    fi
fi

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up port-forward...${NC}"
    kill $PORT_FORWARD_PID 2>/dev/null || true
    pkill -f "port-forward.*demo-app" 2>/dev/null || true
}

# Set trap to cleanup on exit
trap cleanup EXIT INT TERM
echo ""

# Function to send requests
send_requests() {
    local user_id=$1
    local endpoint=$2
    local count=0
    
    while [ $count -lt $REQUESTS_PER_USER ]; do
        curl -s "$SERVICE_URL$endpoint" > /dev/null 2>&1
        count=$((count + 1))
        
        # Small delay to simulate realistic traffic
        sleep 0.01
    done
}

# Function to monitor scaling
monitor_scaling() {
    echo -e "${BLUE}Monitoring HPA and Pods (press Ctrl+C to stop)...${NC}"
    echo ""
    
    while true; do
        clear
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}Real-time Scaling Status${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        
        echo -e "${YELLOW}HPA Status:${NC}"
        kubectl get hpa demo-app-hpa -n $NAMESPACE 2>/dev/null || echo "HPA not found"
        echo ""
        
        echo -e "${YELLOW}Pod Status:${NC}"
        kubectl get pods -n $NAMESPACE -l app=demo-app
        echo ""
        
        echo -e "${YELLOW}Recent Events:${NC}"
        kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | grep -E "demo-app|Scaled" | tail -5
        echo ""
        
        sleep 5
    done
}

# Start monitoring in background
monitor_scaling &
MONITOR_PID=$!

# Trap to cleanup background process
trap "kill $MONITOR_PID 2>/dev/null; exit" INT TERM EXIT

echo -e "${GREEN}Starting load test...${NC}"
echo -e "${YELLOW}Sending traffic to trigger auto-scaling${NC}"
echo ""

# Phase 1: Warm-up (light load)
echo -e "${BLUE}Phase 1: Warm-up (30s)${NC}"
for i in $(seq 1 10); do
    send_requests $i "/" &
done
wait
sleep 30

# Phase 2: Ramp-up (increasing load)
echo -e "${BLUE}Phase 2: Ramp-up (60s)${NC}"
for i in $(seq 1 $((CONCURRENT_USERS / 2))); do
    send_requests $i "/" &
done
wait
sleep 60

# Phase 3: Peak load
echo -e "${BLUE}Phase 3: Peak load (${DURATION}s)${NC}"
START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION))

while [ $(date +%s) -lt $END_TIME ]; do
    # Send requests in batches
    for i in $(seq 1 $CONCURRENT_USERS); do
        # Mix of endpoints
        if [ $((i % 3)) -eq 0 ]; then
            curl -s "$SERVICE_URL/load" > /dev/null 2>&1 &
        else
            curl -s "$SERVICE_URL/" > /dev/null 2>&1 &
        fi
    done
    
    # Wait a bit before next batch
    sleep 0.5
    
    # Limit background jobs
    while [ $(jobs -r | wc -l) -gt $CONCURRENT_USERS ]; do
        sleep 0.1
    done
done

# Wait for remaining requests
wait

# Phase 4: Cool-down
echo -e "${BLUE}Phase 4: Cool-down (60s)${NC}"
echo -e "${YELLOW}Stopping traffic to observe scale-down${NC}"
sleep 60

# Cleanup
kill $MONITOR_PID 2>/dev/null || true

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Load test completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Final Status:${NC}"
kubectl get hpa demo-app-hpa -n $NAMESPACE
echo ""
kubectl get pods -n $NAMESPACE -l app=demo-app
echo ""
echo -e "${BLUE}Check Grafana dashboard for detailed metrics:${NC}"
echo -e "${BLUE}kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80${NC}"
echo -e "${BLUE}Then open: http://localhost:3000${NC}"

# Made with Bob
