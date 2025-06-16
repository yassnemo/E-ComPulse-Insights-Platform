#!/bin/bash

# Kafka Topic Management Script
# Creates and configures topics for the E-ComPulse platform

set -e

# Configuration
KAFKA_BOOTSTRAP_SERVERS=${KAFKA_BOOTSTRAP_SERVERS:-"localhost:9092"}
REPLICATION_FACTOR=${REPLICATION_FACTOR:-3}
MIN_INSYNC_REPLICAS=${MIN_INSYNC_REPLICAS:-2}

echo "Creating Kafka topics for E-ComPulse platform..."
echo "Bootstrap servers: $KAFKA_BOOTSTRAP_SERVERS"
echo "Replication factor: $REPLICATION_FACTOR"

# Function to create topic with retry
create_topic() {
    local topic_name=$1
    local partitions=$2
    local configs=$3
    
    echo "Creating topic: $topic_name with $partitions partitions"
    
    # Create topic
    kafka-topics.sh --create \
        --bootstrap-server "$KAFKA_BOOTSTRAP_SERVERS" \
        --topic "$topic_name" \
        --partitions "$partitions" \
        --replication-factor "$REPLICATION_FACTOR" \
        --if-not-exists \
        --config "min.insync.replicas=$MIN_INSYNC_REPLICAS" \
        $configs
    
    # Verify topic creation
    if kafka-topics.sh --describe --bootstrap-server "$KAFKA_BOOTSTRAP_SERVERS" --topic "$topic_name" >/dev/null 2>&1; then
        echo "✓ Topic $topic_name created successfully"
    else
        echo "✗ Failed to create topic $topic_name"
        exit 1
    fi
}

# Raw events topic - High throughput ingestion
create_topic "ecommerce-events-raw" 24 \
    "--config retention.ms=604800000 \
     --config segment.ms=86400000 \
     --config compression.type=snappy \
     --config cleanup.policy=delete \
     --config message.max.bytes=1048576"

# Enriched events topic - Processed events with metadata
create_topic "ecommerce-events-enriched" 12 \
    "--config retention.ms=2592000000 \
     --config segment.ms=86400000 \
     --config compression.type=snappy \
     --config cleanup.policy=delete \
     --config message.max.bytes=2097152"

# Dead letter queue - Failed events for investigation
create_topic "ecommerce-events-dlq" 1 \
    "--config retention.ms=7776000000 \
     --config segment.ms=86400000 \
     --config compression.type=gzip \
     --config cleanup.policy=delete \
     --config message.max.bytes=2097152"

# User sessions topic - Session aggregation
create_topic "user-sessions" 12 \
    "--config retention.ms=2592000000 \
     --config segment.ms=86400000 \
     --config compression.type=snappy \
     --config cleanup.policy=compact \
     --config delete.retention.ms=86400000"

# Real-time metrics topic - High-frequency aggregated metrics
create_topic "realtime-metrics" 6 \
    "--config retention.ms=259200000 \
     --config segment.ms=3600000 \
     --config compression.type=snappy \
     --config cleanup.policy=delete \
     --config message.max.bytes=524288"

# Alerts topic - System and business alerts
create_topic "system-alerts" 3 \
    "--config retention.ms=2592000000 \
     --config segment.ms=86400000 \
     --config compression.type=gzip \
     --config cleanup.policy=delete"

# Data quality topic - Schema validation and data quality issues
create_topic "data-quality-issues" 1 \
    "--config retention.ms=7776000000 \
     --config segment.ms=86400000 \
     --config compression.type=gzip \
     --config cleanup.policy=delete"

# Configuration changes topic - Feature flags and runtime configuration
create_topic "config-changes" 1 \
    "--config retention.ms=31536000000 \
     --config segment.ms=86400000 \
     --config compression.type=gzip \
     --config cleanup.policy=compact \
     --config delete.retention.ms=604800000"

echo ""
echo "Topic creation completed. Current topics:"
kafka-topics.sh --list --bootstrap-server "$KAFKA_BOOTSTRAP_SERVERS"

echo ""
echo "Topic configurations:"
for topic in ecommerce-events-raw ecommerce-events-enriched ecommerce-events-dlq user-sessions realtime-metrics system-alerts data-quality-issues config-changes; do
    echo "=== $topic ==="
    kafka-topics.sh --describe --bootstrap-server "$KAFKA_BOOTSTRAP_SERVERS" --topic "$topic"
    echo ""
done
