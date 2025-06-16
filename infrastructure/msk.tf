# MSK (Managed Streaming for Apache Kafka) Configuration

# KMS key for MSK encryption
resource "aws_kms_key" "msk" {
  description = "KMS key for MSK cluster encryption"
  
  tags = {
    Name = "${var.project_name}-${var.environment}-msk-key"
  }
}

resource "aws_kms_alias" "msk" {
  name          = "alias/${var.project_name}-${var.environment}-msk"
  target_key_id = aws_kms_key.msk.key_id
}

# CloudWatch log group for MSK
resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-${var.environment}-msk-logs"
  }
}

# MSK cluster configuration
resource "aws_msk_configuration" "main" {
  kafka_versions = [var.kafka_version]
  name           = "${var.project_name}-${var.environment}-config"
  description    = "MSK configuration for ${var.project_name} ${var.environment}"

  server_properties = <<PROPERTIES
# Broker settings for high throughput
num.network.threads=8
num.io.threads=16
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600

# Log settings for performance
log.retention.hours=168
log.retention.bytes=1073741824
log.segment.bytes=1073741824
log.cleanup.policy=delete

# Replication settings for durability
default.replication.factor=3
min.insync.replicas=2
replica.fetch.max.bytes=1048576

# Producer optimizations
compression.type=snappy
message.max.bytes=1000000

# Consumer optimizations
fetch.message.max.bytes=1048576

# JVM heap settings
auto.create.topics.enable=false
delete.topic.enable=true

# Security settings
security.inter.broker.protocol=PLAINTEXT
PROPERTIES
}

# MSK cluster
resource "aws_msk_cluster" "main" {
  cluster_name           = "${var.project_name}-${var.environment}"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.kafka_broker_count * length(module.vpc.private_subnets)

  broker_node_group_info {
    instance_type   = var.kafka_instance_type
    client_subnets  = module.vpc.private_subnets
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.kafka_ebs_volume_size
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.main.arn
    revision = aws_msk_configuration.main.latest_revision
  }

  encryption_info {
    encryption_at_rest_kms_key_id = aws_kms_key.msk.arn
    
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
      
      s3 {
        enabled = true
        bucket  = aws_s3_bucket.data_lake.bucket
        prefix  = "msk-logs/"
      }
    }
  }

  monitoring_info {
    enhanced_monitoring = "PER_TOPIC_PER_BROKER"
    open_monitoring {
      prometheus {
        jmx_exporter {
          enabled_in_broker = true
        }
        node_exporter {
          enabled_in_broker = true
        }
      }
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-msk"
  }
}

# MSK Connect configuration for Kafka Connect
resource "aws_mskconnect_custom_plugin" "debezium" {
  name         = "${var.project_name}-${var.environment}-debezium"
  content_type = "ZIP"
  description  = "Debezium connector for CDC from databases"

  location {
    s3 {
      bucket_arn = aws_s3_bucket.data_lake.arn
      file_key   = "connectors/debezium-connector.zip"
    }
  }
}

# IAM role for MSK Connect
resource "aws_iam_role" "msk_connect" {
  name = "${var.project_name}-${var.environment}-msk-connect"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "kafkaconnect.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "msk_connect" {
  name = "${var.project_name}-${var.environment}-msk-connect-policy"
  role = aws_iam_role.msk_connect.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeCluster"
        ]
        Resource = aws_msk_cluster.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:*Topic*",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData"
        ]
        Resource = "${aws_msk_cluster.main.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = "${aws_msk_cluster.main.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.data_lake.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.data_lake.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLog*"
        ]
        Resource = "*"
      }
    ]
  })
}
