from flask import Flask, Response
import time
import random
from prometheus_client import Counter, Gauge, Histogram, generate_latest, REGISTRY
import os

app = Flask(__name__)

# Prometheus metrics
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

REQUEST_LATENCY = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint']
)

REQUESTS_PER_SECOND = Gauge(
    'http_requests_per_second',
    'Current requests per second'
)

ACTIVE_REQUESTS = Gauge(
    'http_active_requests',
    'Number of active requests'
)

# Track requests for rate calculation
request_times = []
request_window = 10  # seconds

def calculate_request_rate():
    """Calculate requests per second over the last window"""
    current_time = time.time()
    # Remove old requests outside the window
    global request_times
    request_times = [t for t in request_times if current_time - t < request_window]
    
    if len(request_times) > 0:
        rate = len(request_times) / request_window
    else:
        rate = 0
    
    REQUESTS_PER_SECOND.set(rate)
    return rate

@app.route('/')
def index():
    """Main endpoint that simulates work"""
    ACTIVE_REQUESTS.inc()
    start_time = time.time()
    
    try:
        # Record request time
        request_times.append(time.time())
        
        # Simulate some CPU work
        work_duration = random.uniform(0.01, 0.1)
        end_time = time.time() + work_duration
        result = 0
        while time.time() < end_time:
            result += sum(range(1000))
        
        # Calculate current request rate
        rate = calculate_request_rate()
        
        REQUEST_COUNT.labels(method='GET', endpoint='/', status='200').inc()
        
        response = f"""
        <html>
        <head><title>Auto-Scaling Demo</title></head>
        <body>
            <h1>Kubernetes Auto-Scaling Demo</h1>
            <p>Pod: {os.getenv('HOSTNAME', 'unknown')}</p>
            <p>Current Request Rate: {rate:.2f} req/s</p>
            <p>Work completed: {result}</p>
            <p>Processing time: {work_duration:.3f}s</p>
            <hr>
            <p>Send traffic to this endpoint to trigger auto-scaling!</p>
            <p>Metrics available at <a href="/metrics">/metrics</a></p>
        </body>
        </html>
        """
        
        return response, 200
    
    finally:
        REQUEST_LATENCY.labels(method='GET', endpoint='/').observe(time.time() - start_time)
        ACTIVE_REQUESTS.dec()

@app.route('/health')
def health():
    """Health check endpoint"""
    REQUEST_COUNT.labels(method='GET', endpoint='/health', status='200').inc()
    return {'status': 'healthy'}, 200

@app.route('/metrics')
def metrics():
    """Prometheus metrics endpoint"""
    calculate_request_rate()  # Update rate before exposing metrics
    return Response(generate_latest(REGISTRY), mimetype='text/plain')

@app.route('/load')
def load():
    """Endpoint to simulate heavy load"""
    ACTIVE_REQUESTS.inc()
    start_time = time.time()
    
    try:
        request_times.append(time.time())
        
        # Simulate heavier CPU work
        work_duration = random.uniform(0.1, 0.5)
        end_time = time.time() + work_duration
        result = 0
        while time.time() < end_time:
            result += sum(range(10000))
        
        rate = calculate_request_rate()
        REQUEST_COUNT.labels(method='GET', endpoint='/load', status='200').inc()
        
        return {
            'pod': os.getenv('HOSTNAME', 'unknown'),
            'rate': f'{rate:.2f} req/s',
            'work_time': f'{work_duration:.3f}s'
        }, 200
    
    finally:
        REQUEST_LATENCY.labels(method='GET', endpoint='/load').observe(time.time() - start_time)
        ACTIVE_REQUESTS.dec()

if __name__ == '__main__':
    # Initialize metrics
    REQUESTS_PER_SECOND.set(0)
    ACTIVE_REQUESTS.set(0)
    
    # Run the app
    app.run(host='0.0.0.0', port=5000, debug=False)

# Made with Bob
