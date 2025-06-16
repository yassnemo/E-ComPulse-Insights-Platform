# Spark Structured Streaming Jobs

This module contains Apache Spark Structured Streaming applications for real-time processing of e-commerce events with exactly-once semantics and stateful aggregations.

## Components

### 1. Event Enrichment Job
- **Purpose**: Enrich raw events with user profiles, product metadata, and geolocation data
- **Processing**: Stream-stream joins with Redis/DynamoDB lookups
- **Output**: Enriched events to downstream topics and data lake

### 2. Session Analytics Job
- **Purpose**: Real-time session analysis and user behavior tracking
- **Processing**: Session window aggregations with watermarking
- **Output**: Session metrics, conversion funnels, abandonment alerts

### 3. Real-time Metrics Job
- **Purpose**: Generate business metrics in real-time
- **Processing**: Tumbling and sliding window aggregations
- **Output**: KPIs, dashboards data, alerting metrics

### 4. Anomaly Detection Job
- **Purpose**: Detect unusual patterns and potential fraud
- **Processing**: ML-based anomaly detection with streaming updates
- **Output**: Alerts, risk scores, flagged transactions

## Key Features

### Exactly-Once Processing
- Kafka source with checkpointing on S3/EFS
- Idempotent sinks with deduplication
- Transactional writes to data warehouse

### State Management
- Stateful operations with checkpointing
- Watermarking for late data handling
- State store optimization for performance

### Fault Tolerance
- Automatic recovery from failures
- Backup checkpoints for disaster recovery
- Circuit breakers for downstream dependencies

## Performance Tuning

### Spark Configuration
- **Shuffle partitions**: 200 (optimized for cluster size)
- **Executor memory**: 4GB with 0.8 fraction for storage
- **Executor cores**: 4 cores per executor
- **Dynamic allocation**: Enabled with auto-scaling

### Streaming Configuration
- **Trigger interval**: 10 seconds for micro-batches
- **Max files per trigger**: 1000 for source rate limiting
- **Watermark**: 10 minutes for late data tolerance

## Deployment

```bash
# Build Spark application
cd spark-streaming
./build.sh

# Deploy to Kubernetes
kubectl apply -f kubernetes/spark-jobs.yaml

# Submit job to Spark cluster
spark-submit \
  --class com.ecompulse.streaming.EventEnrichmentJob \
  --master k8s://https://eks-cluster-endpoint \
  --deploy-mode cluster \
  target/ecompulse-streaming-1.0.jar
```

## Monitoring

### Structured Streaming UI
- Job progress and batch details
- Input/output rates and processing times
- State store metrics and watermarks

### Custom Metrics
- Business KPIs (conversion rates, revenue)
- Data quality metrics (schema violations, null rates)
- Performance metrics (latency, throughput)
