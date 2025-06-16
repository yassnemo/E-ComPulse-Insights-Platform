# E-ComPulse Monitoring & Observability

## 📊 Overview

This directory contains comprehensive monitoring, alerting, and observability configurations for the E-ComPulse Insights Platform. The monitoring stack includes Prometheus for metrics collection, Grafana for visualization, and custom exporters for business-specific metrics.

## 🏗️ Architecture

```mermaid
graph TB
    subgraph "Data Sources"
        APP[Applications]
        KAFKA[Kafka Cluster]
        SPARK[Spark Jobs]
        K8S[Kubernetes]
        AWS[AWS Services]
    end
    
    subgraph "Metrics Collection"
        PROM[Prometheus Server]
        EXPORTERS[Custom Exporters]
        JAEGER[Jaeger Tracing]
    end
    
    subgraph "Visualization & Alerting"
        GRAFANA[Grafana Dashboards]
        ALERT[Alert Manager]
        SLACK[Slack Notifications]
    end
    
    APP --> PROM
    KAFKA --> PROM
    SPARK --> PROM
    K8S --> PROM
    AWS --> PROM
    EXPORTERS --> PROM
    
    PROM --> GRAFANA
    PROM --> ALERT
    ALERT --> SLACK
```

## 📁 Directory Structure

```
monitoring/
├── README.md                    # This file
├── prometheus/                  # Prometheus configuration
│   ├── prometheus.yml          # Main Prometheus config
│   ├── rules/                  # Alerting rules
│   └── exporters/              # Custom exporters
├── grafana/                    # Grafana dashboards
│   ├── dashboards/             # Dashboard JSON definitions
│   ├── provisioning/           # Dashboard provisioning
│   └── plugins/                # Custom plugins
├── alertmanager/               # AlertManager configuration
│   ├── alertmanager.yml        # Main AlertManager config
│   └── templates/              # Alert templates
└── jaeger/                     # Distributed tracing
    └── jaeger.yml              # Jaeger configuration
```

## 🚀 Quick Start

### 1. Deploy Monitoring Stack

```bash
# Deploy via Helm
helm install monitoring ./k8s/helm/monitoring -n monitoring --create-namespace

# Or deploy individual components
kubectl apply -f monitoring/prometheus/
kubectl apply -f monitoring/grafana/
kubectl apply -f monitoring/alertmanager/
```

### 2. Access Dashboards

```bash
# Grafana (Default: admin/admin)
kubectl port-forward svc/grafana 3000:3000 -n monitoring

# Prometheus
kubectl port-forward svc/prometheus 9090:9090 -n monitoring

# AlertManager
kubectl port-forward svc/alertmanager 9093:9093 -n monitoring
```

### 3. Import Dashboards

Dashboards are automatically provisioned, but you can also import manually:

1. **Platform Overview**: `dashboards/platform-overview.json`
2. **Kafka Monitoring**: `dashboards/kafka-dashboard.json`
3. **Spark Streaming**: `dashboards/spark-streaming.json`
4. **Business Analytics**: `dashboards/business-analytics.json`
5. **Infrastructure**: `dashboards/infrastructure.json`

## 📈 Key Metrics

### Application Metrics

| Metric | Description | Type | Labels |
|--------|-------------|------|--------|
| `ecompulse_events_total` | Total events processed | Counter | `event_type`, `source` |
| `ecompulse_events_per_second` | Event processing rate | Gauge | `event_type` |
| `ecompulse_processing_duration_seconds` | Event processing latency | Histogram | `stage`, `job` |
| `ecompulse_errors_total` | Total errors encountered | Counter | `error_type`, `component` |

### Kafka Metrics

| Metric | Description | Type | Labels |
|--------|-------------|------|--------|
| `kafka_topic_partitions` | Number of partitions per topic | Gauge | `topic` |
| `kafka_consumer_lag` | Consumer group lag | Gauge | `group`, `topic`, `partition` |
| `kafka_broker_bytes_in_per_sec` | Bytes received per second | Gauge | `broker` |
| `kafka_broker_bytes_out_per_sec` | Bytes sent per second | Gauge | `broker` |

### Spark Metrics

| Metric | Description | Type | Labels |
|--------|-------------|------|--------|
| `spark_streaming_batch_duration` | Batch processing duration | Histogram | `job_name` |
| `spark_streaming_records_per_batch` | Records processed per batch | Gauge | `job_name` |
| `spark_executor_memory_used` | Executor memory usage | Gauge | `executor_id` |
| `spark_streaming_scheduling_delay` | Streaming scheduling delay | Gauge | `job_name` |

## 🔔 Alerting Rules

### Critical Alerts

1. **High Error Rate**
   ```yaml
   - alert: HighErrorRate
     expr: rate(ecompulse_errors_total[5m]) > 0.1
     for: 2m
     severity: critical
   ```

2. **Kafka Consumer Lag**
   ```yaml
   - alert: KafkaConsumerLag
     expr: kafka_consumer_lag > 1000
     for: 5m
     severity: warning
   ```

3. **Spark Job Failure**
   ```yaml
   - alert: SparkJobFailure
     expr: spark_streaming_batch_duration > 300
     for: 2m
     severity: critical
   ```

### Infrastructure Alerts

1. **High CPU Usage**
   ```yaml
   - alert: HighCPUUsage
     expr: cpu_usage_percent > 80
     for: 5m
     severity: warning
   ```

2. **High Memory Usage**
   ```yaml
   - alert: HighMemoryUsage
     expr: memory_usage_percent > 85
     for: 3m
     severity: warning
   ```

3. **Disk Space Low**
   ```yaml
   - alert: DiskSpaceLow
     expr: disk_free_percent < 10
     for: 1m
     severity: critical
   ```

## 📊 Dashboard Overview

### 1. Platform Overview Dashboard

- **System Health**: Overall platform status
- **Event Throughput**: Real-time event processing rates
- **Error Rates**: System-wide error tracking
- **Resource Utilization**: CPU, memory, disk usage
- **SLA Metrics**: Availability and performance SLAs

### 2. Kafka Dashboard

- **Broker Metrics**: Throughput, disk usage, network I/O
- **Topic Analysis**: Message rates, partition distribution
- **Consumer Groups**: Lag monitoring, throughput
- **Cluster Health**: Replica sync, leader election

### 3. Spark Streaming Dashboard

- **Job Performance**: Batch duration, throughput
- **Resource Usage**: Executor memory, CPU utilization
- **Data Quality**: Record counts, error rates
- **Checkpoint Health**: Checkpoint duration, failures

### 4. Business Analytics Dashboard

- **E-commerce KPIs**: Conversion rates, revenue metrics
- **User Behavior**: Session analytics, user journeys
- **Product Performance**: Top products, category analysis
- **Real-time Insights**: Live dashboard updates

### 5. Infrastructure Dashboard

- **Kubernetes Metrics**: Pod status, resource usage
- **AWS Services**: EKS, MSK, RDS health
- **Network Performance**: Ingress/egress traffic
- **Security Events**: Failed authentication, anomalies

## 🔧 Configuration

### Custom Metrics

Add custom metrics to your applications:

```python
from prometheus_client import Counter, Histogram, Gauge

# Event counter
EVENT_COUNTER = Counter(
    'ecompulse_events_total',
    'Total events processed',
    ['event_type', 'source']
)

# Processing latency
PROCESSING_DURATION = Histogram(
    'ecompulse_processing_duration_seconds',
    'Event processing duration',
    ['stage', 'job']
)

# Active users gauge
ACTIVE_USERS = Gauge(
    'ecompulse_active_users',
    'Number of active users'
)
```

### Dashboard Variables

Use these variables in Grafana dashboards:

- `$environment`: Environment (dev/staging/prod)
- `$cluster`: Kubernetes cluster name
- `$namespace`: Application namespace
- `$job`: Spark job name
- `$topic`: Kafka topic name
- `$timerange`: Time range selector

## 🚨 Troubleshooting

### Common Issues

1. **Missing Metrics**
   ```bash
   # Check if targets are up
   curl http://localhost:9090/api/v1/targets
   
   # Verify service discovery
   kubectl get servicemonitors -n monitoring
   ```

2. **Dashboard Loading Issues**
   ```bash
   # Check Grafana logs
   kubectl logs deployment/grafana -n monitoring
   
   # Verify data source connection
   curl http://admin:admin@localhost:3000/api/datasources
   ```

3. **Alert Not Firing**
   ```bash
   # Check AlertManager status
   curl http://localhost:9093/api/v1/status
   
   # Verify alert rules
   curl http://localhost:9090/api/v1/rules
   ```

### Performance Tuning

1. **Prometheus Storage**
   ```yaml
   # Increase retention and storage
   prometheus:
     retention: "30d"
     storage:
       volumeClaimTemplate:
         spec:
           resources:
             requests:
               storage: 500Gi
   ```

2. **Grafana Optimization**
   ```yaml
   # Configure caching
   grafana:
     config:
       caching:
         enabled: true
       feature_toggles:
         enable: "publicDashboards,panelTitleSearch"
   ```

## 📞 Support

For monitoring and observability support:
- 📧 **Email**: monitoring@ecompulse.com
- 📚 **Documentation**: https://docs.ecompulse.com/monitoring
- 🔧 **Runbooks**: `/docs/runbooks/monitoring/`
