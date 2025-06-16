# Kafka Configuration & Client Code

This module contains Kafka topic configurations, producer/consumer examples, and best practices for reliable event streaming in the E-ComPulse platform.

## Components

### 1. Topic Configuration
- **Raw Events**: High-throughput ingestion with optimal partitioning
- **Enriched Events**: Processed events with additional metadata
- **Dead Letter Queue**: Failed events for investigation and reprocessing

### 2. Producer Patterns
- **High-throughput producers** with optimal batching and compression
- **Exactly-once semantics** with idempotent producers
- **Error handling** with retry logic and circuit breakers

### 3. Consumer Patterns
- **Auto-scaling consumer groups** for elastic processing
- **Back-pressure handling** to prevent overwhelming downstream systems
- **Offset management** for reliable processing guarantees

## Topic Design

### Partitioning Strategy
- **Raw events**: Partitioned by user_id for session locality
- **Enriched events**: Partitioned by event_type for parallel processing
- **Dead letter**: Single partition for sequential investigation

### Retention Policy
- **Raw events**: 7 days (high volume, short-term processing)
- **Enriched events**: 30 days (processed data, longer retention)
- **Dead letter**: 90 days (investigation and compliance)

## Performance Tuning

### Producer Configuration
- **Batch size**: 16KB for optimal network utilization
- **Linger time**: 5ms for low-latency batching
- **Compression**: Snappy for balanced CPU/network trade-off
- **Acks**: all for durability guarantee

### Consumer Configuration
- **Fetch size**: 1MB for efficient bulk processing
- **Session timeout**: 30s for failure detection
- **Auto-commit**: Disabled for manual offset management
- **Isolation level**: read_committed for exactly-once processing

## Monitoring

### Key Metrics
- **Producer lag**: Time between event generation and Kafka delivery
- **Consumer lag**: Offset difference between latest and processed
- **Throughput**: Events per second per topic/partition
- **Error rate**: Failed messages per minute

### Alerting Thresholds
- Consumer lag > 1000 messages
- Error rate > 1% over 5 minutes
- Producer send failures > 10 per minute
