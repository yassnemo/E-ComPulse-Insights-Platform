# Data Ingestion Modules

This module contains components for ingesting e-commerce events from both synthetic data generators and real-world front-end applications.

## Components

### 1. Synthetic Event Generator
- **Purpose**: Generate realistic e-commerce events for testing and demonstration
- **Capability**: Up to 200,000 events per minute configurable rate
- **Events**: Page views, product views, cart actions, purchases, user sessions

### 2. Real-World Front-End Tracker
- **Web Tracker**: JavaScript SDK for web applications (React, Angular, plain HTML)
- **Mobile SDK**: Integration examples for Android and iOS applications
- **Event Transport**: Kafka REST Proxy for reliable event delivery

### 3. Transition Strategy
- **Feature Flags**: Seamless switching between synthetic and real data
- **Blue/Green Topics**: Zero-downtime data source transitions
- **Schema Compatibility**: Backward-compatible event schemas

## Event Schema

All events follow a standardized schema for consistent processing:

```json
{
  "event_id": "uuid",
  "event_type": "page_view|product_view|add_to_cart|purchase|user_login",
  "timestamp": "2024-01-01T12:00:00Z",
  "user_id": "uuid",
  "session_id": "uuid",
  "source": "web|mobile|synthetic",
  "properties": {
    "page_url": "string",
    "product_id": "string",
    "product_category": "string",
    "price": "number",
    "currency": "string",
    "user_agent": "string",
    "ip_address": "string"
  },
  "metadata": {
    "sdk_version": "string",
    "platform": "string",
    "environment": "prod|dev|staging"
  }
}
```

## Deployment

```bash
# Build Docker images
docker build -t ecompulse/synthetic-generator:latest ./synthetic-generator
docker build -t ecompulse/web-tracker:latest ./web-tracker

# Deploy to Kubernetes
kubectl apply -f kubernetes/synthetic-generator.yaml
kubectl apply -f kubernetes/web-tracker.yaml
```

## Performance Targets

- **Synthetic Generator**: 200,000 events/minute maximum
- **Web Tracker**: <50ms event capture latency
- **Mobile SDK**: <100ms event capture latency
- **Reliability**: 99.99% event delivery success rate
