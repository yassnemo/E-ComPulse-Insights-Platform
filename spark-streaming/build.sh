#!/bin/bash

# Build script for Spark Streaming jobs
# Builds Docker images and assembles JAR files for deployment

set -e

echo "Building E-ComPulse Spark Streaming Jobs..."

# Configuration
DOCKER_REGISTRY=${DOCKER_REGISTRY:-"ecompulse"}
VERSION=${VERSION:-"1.0.0"}
SCALA_VERSION="2.12"
SPARK_VERSION="3.4.1"

# Clean previous builds
echo "Cleaning previous builds..."
sbt clean

# Run tests
echo "Running tests..."
sbt test

# Build fat JAR with all dependencies
echo "Building assembly JAR..."
sbt assembly

# Create target directory structure
mkdir -p target/docker

# Copy JAR to docker directory
cp target/scala-${SCALA_VERSION}/ecompulse-streaming-${VERSION}-assembly.jar target/docker/

echo "Building Docker image for Spark applications..."

# Create Dockerfile for Spark applications
cat > target/docker/Dockerfile << EOF
# Multi-stage build for Spark Streaming applications
FROM openjdk:8-jre-slim as base

# Install required packages
RUN apt-get update && apt-get install -y \\
    curl \\
    procps \\
    && rm -rf /var/lib/apt/lists/*

# Create spark user
RUN groupadd -r spark && useradd -r -g spark spark

# Set up Spark environment
ENV SPARK_HOME=/opt/spark
ENV PATH=\$PATH:\$SPARK_HOME/bin:\$SPARK_HOME/sbin
ENV SPARK_CONF_DIR=\$SPARK_HOME/conf
ENV SPARK_LOG_DIR=/tmp/spark-logs

# Download and install Spark
RUN curl -O https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz \\
    && tar -xzf spark-${SPARK_VERSION}-bin-hadoop3.tgz \\
    && mv spark-${SPARK_VERSION}-bin-hadoop3 \$SPARK_HOME \\
    && rm spark-${SPARK_VERSION}-bin-hadoop3.tgz

# Create necessary directories
RUN mkdir -p \$SPARK_LOG_DIR \\
    && mkdir -p /opt/spark-apps \\
    && mkdir -p /opt/spark-data \\
    && chown -R spark:spark \$SPARK_HOME \\
    && chown -R spark:spark \$SPARK_LOG_DIR \\
    && chown -R spark:spark /opt/spark-apps \\
    && chown -R spark:spark /opt/spark-data

# Production stage
FROM base as production

# Copy application JAR
COPY ecompulse-streaming-${VERSION}-assembly.jar /opt/spark-apps/

# Copy Spark configuration
COPY spark-defaults.conf \$SPARK_CONF_DIR/
COPY log4j.properties \$SPARK_CONF_DIR/

# Set permissions
RUN chown spark:spark /opt/spark-apps/ecompulse-streaming-${VERSION}-assembly.jar

# Switch to spark user
USER spark

# Set working directory
WORKDIR /opt/spark-apps

# Environment variables
ENV SPARK_APPLICATION_JAR_LOCATION=/opt/spark-apps/ecompulse-streaming-${VERSION}-assembly.jar
ENV SPARK_APPLICATION_MAIN_CLASS=com.ecompulse.streaming.EventEnrichmentJob

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \\
  CMD curl -f http://localhost:4040 || exit 1

# Default command
CMD [\$SPARK_HOME/bin/spark-submit, \\
     --class, \$SPARK_APPLICATION_MAIN_CLASS, \\
     --master, "local[*]", \\
     --deploy-mode, "client", \\
     --conf, "spark.driver.memory=2g", \\
     --conf, "spark.executor.memory=2g", \\
     --conf, "spark.sql.adaptive.enabled=true", \\
     --conf, "spark.sql.adaptive.coalescePartitions.enabled=true", \\
     \$SPARK_APPLICATION_JAR_LOCATION]
EOF

# Create Spark configuration files
cat > target/docker/spark-defaults.conf << EOF
# Spark Configuration for E-ComPulse Streaming Jobs

# Performance settings
spark.sql.adaptive.enabled true
spark.sql.adaptive.coalescePartitions.enabled true
spark.sql.adaptive.advisoryPartitionSizeInBytes 128MB
spark.sql.adaptive.skewJoin.enabled true

# Serialization
spark.serializer org.apache.spark.serializer.KryoSerializer
spark.kryo.unsafe true
spark.kryo.referenceTracking false

# Memory settings
spark.executor.memory 4g
spark.driver.memory 2g
spark.executor.memoryFraction 0.8
spark.executor.memoryStorageFraction 0.2

# Shuffle settings
spark.sql.shuffle.partitions 200
spark.shuffle.service.enabled true
spark.shuffle.compress true
spark.shuffle.spill.compress true

# Checkpoint settings
spark.sql.streaming.checkpointLocation s3a://ecompulse-prod-data-lake/checkpoints
spark.sql.streaming.stateStore.providerClass org.apache.spark.sql.execution.streaming.state.HDFSBackedStateStoreProvider

# Kafka settings
spark.sql.streaming.kafka.useDeprecatedOffsetFetching false

# S3 settings
spark.hadoop.fs.s3a.impl org.apache.hadoop.fs.s3a.S3AFileSystem
spark.hadoop.fs.s3a.fast.upload true
spark.hadoop.fs.s3a.block.size 128M
spark.hadoop.fs.s3a.multipart.size 128M
spark.hadoop.fs.s3a.multipart.threshold 512M

# Monitoring
spark.ui.enabled true
spark.ui.port 4040
spark.eventLog.enabled true
spark.eventLog.dir s3a://ecompulse-prod-data-lake/spark-events

# Dynamic allocation
spark.dynamicAllocation.enabled true
spark.dynamicAllocation.minExecutors 1
spark.dynamicAllocation.maxExecutors 10
spark.dynamicAllocation.initialExecutors 2
EOF

cat > target/docker/log4j.properties << EOF
# Root logger
log4j.rootLogger=INFO, console

# Console appender
log4j.appender.console=org.apache.log4j.ConsoleAppender
log4j.appender.console.layout=org.apache.log4j.PatternLayout
log4j.appender.console.layout.ConversionPattern=%d{yyyy-MM-dd HH:mm:ss} %-5p %c{1}:%L - %m%n

# Reduce verbosity for some loggers
log4j.logger.org.apache.spark=WARN
log4j.logger.org.apache.hadoop=WARN
log4j.logger.org.apache.kafka=WARN
log4j.logger.org.spark_project=WARN
log4j.logger.org.apache.zookeeper=WARN

# Application loggers
log4j.logger.com.ecompulse=INFO
EOF

# Build Docker image
docker build -t ${DOCKER_REGISTRY}/spark-streaming:${VERSION} target/docker/

# Tag as latest
docker tag ${DOCKER_REGISTRY}/spark-streaming:${VERSION} ${DOCKER_REGISTRY}/spark-streaming:latest

echo "Docker image built successfully: ${DOCKER_REGISTRY}/spark-streaming:${VERSION}"

# Build specific job images
jobs=("event-enrichment" "session-analytics" "realtime-metrics")

for job in "${jobs[@]}"; do
    echo "Building Docker image for $job job..."
    
    # Create job-specific Dockerfile
    cat > target/docker/Dockerfile.${job} << EOF
FROM ${DOCKER_REGISTRY}/spark-streaming:${VERSION}

# Set job-specific main class
ENV SPARK_APPLICATION_MAIN_CLASS=com.ecompulse.streaming.$(echo $job | sed 's/-//g' | awk '{print toupper(substr($0,1,1)) substr($0,2)}')Job

# Job-specific configuration
COPY ${job}-config.conf \$SPARK_CONF_DIR/

# Override default command for this job
CMD [\$SPARK_HOME/bin/spark-submit, \\
     --class, \$SPARK_APPLICATION_MAIN_CLASS, \\
     --master, "local[*]", \\
     --deploy-mode, "client", \\
     --properties-file, \$SPARK_CONF_DIR/${job}-config.conf, \\
     \$SPARK_APPLICATION_JAR_LOCATION]
EOF

    # Create job-specific configuration
    cat > target/docker/${job}-config.conf << EOF
# Configuration for $job job
spark.app.name=ecompulse-$job
spark.executor.instances=3
spark.executor.cores=2
spark.executor.memory=4g
spark.driver.memory=2g
EOF

    # Build job-specific image
    docker build -f target/docker/Dockerfile.${job} -t ${DOCKER_REGISTRY}/spark-${job}:${VERSION} target/docker/
    docker tag ${DOCKER_REGISTRY}/spark-${job}:${VERSION} ${DOCKER_REGISTRY}/spark-${job}:latest
    
    echo "Job-specific image built: ${DOCKER_REGISTRY}/spark-${job}:${VERSION}"
done

# Create Kubernetes manifests
echo "Creating Kubernetes manifests..."
mkdir -p target/k8s

# Create SparkApplication CRD manifest for event enrichment
cat > target/k8s/event-enrichment-sparkapp.yaml << EOF
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: event-enrichment-job
  namespace: spark-jobs
spec:
  type: Scala
  mode: cluster
  image: ${DOCKER_REGISTRY}/spark-event-enrichment:${VERSION}
  imagePullPolicy: Always
  mainClass: com.ecompulse.streaming.EventEnrichmentJob
  mainApplicationFile: local:///opt/spark-apps/ecompulse-streaming-${VERSION}-assembly.jar
  sparkVersion: "${SPARK_VERSION}"
  
  driver:
    cores: 1
    memory: "2g"
    serviceAccount: spark-driver
    env:
      - name: KAFKA_BOOTSTRAP_SERVERS
        value: "kafka-service:9092"
      - name: AWS_REGION
        value: "us-west-2"
    
  executor:
    cores: 2
    instances: 3
    memory: "4g"
    env:
      - name: KAFKA_BOOTSTRAP_SERVERS
        value: "kafka-service:9092"
      - name: AWS_REGION
        value: "us-west-2"
  
  monitoring:
    exposeDriverMetrics: true
    exposeExecutorMetrics: true
    prometheus:
      jmxExporterJar: "/opt/spark/jars/jmx_prometheus_javaagent-0.17.2.jar"
      port: 8090
  
  restartPolicy:
    type: OnFailure
    onFailureRetries: 5
    onFailureRetryInterval: 30
    onSubmissionFailureRetries: 3
    onSubmissionFailureRetryInterval: 60
EOF

echo "Build completed successfully!"
echo ""
echo "Built artifacts:"
echo "- JAR: target/scala-${SCALA_VERSION}/ecompulse-streaming-${VERSION}-assembly.jar"
echo "- Docker images:"
echo "  - ${DOCKER_REGISTRY}/spark-streaming:${VERSION}"
for job in "${jobs[@]}"; do
    echo "  - ${DOCKER_REGISTRY}/spark-${job}:${VERSION}"
done
echo "- Kubernetes manifests: target/k8s/"
echo ""
echo "Next steps:"
echo "1. Push Docker images to registry:"
echo "   docker push ${DOCKER_REGISTRY}/spark-streaming:${VERSION}"
echo "2. Deploy to Kubernetes:"
echo "   kubectl apply -f target/k8s/"
echo "3. Monitor job execution:"
echo "   kubectl logs -f spark-driver-pod-name"
