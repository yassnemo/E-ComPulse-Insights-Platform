# Development Environment Variables
aws_region    = "us-west-2"
environment   = "dev"
project_name  = "ecompulse"

# VPC Configuration
vpc_cidr = "10.1.0.0/16"
private_subnets = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
public_subnets  = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]

# EKS Configuration
cluster_version = "1.28"

# Development node groups - cost optimized
node_groups = {
  general = {
    instance_types = ["t3.medium", "t3.large"]
    capacity_type  = "SPOT"
    min_size      = 1
    max_size      = 5
    desired_size  = 2
    disk_size     = 50
    labels        = { role = "general" }
    taints        = []
  }
  
  compute = {
    instance_types = ["c5.large", "c5.xlarge"]
    capacity_type  = "SPOT"
    min_size      = 0
    max_size      = 5
    desired_size  = 1
    disk_size     = 50
    labels        = { role = "compute" }
    taints = [{
      key    = "compute"
      value  = "true"
      effect = "NO_SCHEDULE"
    }]
  }
}

# MSK Configuration - Development scale
kafka_version         = "2.8.1"
kafka_instance_type   = "kafka.t3.small"   # Smaller for development
kafka_broker_count    = 1                   # Single broker per AZ
kafka_ebs_volume_size = 50                  # Smaller storage

# RDS Configuration - Development scale
rds_instance_class     = "db.t3.micro"     # Smaller for development
rds_allocated_storage  = 20                # Minimal storage
rds_engine_version     = "15.4"

# ElastiCache Configuration - Development scale
redis_node_type        = "cache.t3.micro"  # Smallest instance
redis_num_cache_nodes  = 1                 # Single node
redis_engine_version   = "7.0"

# S3 Configuration
s3_bucket_prefix = "ecompulse-dev"

# Monitoring
enable_cloudwatch   = true
log_retention_days  = 7   # Shorter retention for development

# Cost Optimization
enable_spot_instances = true
auto_scaling_enabled  = true
