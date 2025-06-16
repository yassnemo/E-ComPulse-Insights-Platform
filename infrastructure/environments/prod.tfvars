# Production Environment Variables
aws_region    = "us-west-2"
environment   = "prod"
project_name  = "ecompulse"

# VPC Configuration
vpc_cidr = "10.0.0.0/16"
private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

# EKS Configuration
cluster_version = "1.28"

# Production-grade node groups for high throughput
node_groups = {
  general = {
    instance_types = ["m5.large", "m5.xlarge"]
    capacity_type  = "ON_DEMAND"
    min_size      = 3
    max_size      = 15
    desired_size  = 5
    disk_size     = 100
    labels        = { role = "general" }
    taints        = []
  }
  
  compute_intensive = {
    instance_types = ["c5.2xlarge", "c5.4xlarge"]
    capacity_type  = "SPOT"
    min_size      = 2
    max_size      = 25
    desired_size  = 5
    disk_size     = 200
    labels        = { role = "compute", workload = "spark" }
    taints = [{
      key    = "compute"
      value  = "true"
      effect = "NO_SCHEDULE"
    }]
  }
  
  memory_optimized = {
    instance_types = ["r5.xlarge", "r5.2xlarge"]
    capacity_type  = "ON_DEMAND"
    min_size      = 1
    max_size      = 10
    desired_size  = 2
    disk_size     = 150
    labels        = { role = "memory", workload = "cache" }
    taints = [{
      key    = "memory-optimized"
      value  = "true"
      effect = "NO_SCHEDULE"
    }]
  }
}

# MSK Configuration - Production scale for 100k+ events/minute
kafka_version         = "2.8.1"
kafka_instance_type   = "kafka.m5.xlarge"  # Upgraded for production throughput
kafka_broker_count    = 3                   # 3 brokers per AZ for high availability
kafka_ebs_volume_size = 500                 # Large storage for high retention

# RDS Configuration - Production scale
rds_instance_class     = "db.r5.large"     # Upgraded for production workload
rds_allocated_storage  = 100               # Larger storage for metadata
rds_engine_version     = "15.4"

# ElastiCache Configuration - Production scale
redis_node_type        = "cache.r6g.large" # Upgraded for production caching
redis_num_cache_nodes  = 3                 # Multi-AZ setup
redis_engine_version   = "7.0"

# S3 Configuration
s3_bucket_prefix = "ecompulse-prod"

# Monitoring
enable_cloudwatch   = true
log_retention_days  = 30  # Longer retention for production

# Cost Optimization
enable_spot_instances = true
auto_scaling_enabled  = true
