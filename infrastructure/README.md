# Infrastructure as Code (Terraform)

This module provisions the complete AWS infrastructure for the E-ComPulse platform using Infrastructure as Code principles.

## Architecture Components

- **VPC & Networking**: Multi-AZ setup with public/private subnets
- **EKS Cluster**: Managed Kubernetes with auto-scaling node groups
- **MSK (Kafka)**: Managed Streaming for Apache Kafka
- **RDS**: PostgreSQL for Airflow metadata
- **ElastiCache**: Redis for real-time caching
- **S3**: Data lake storage with lifecycle policies
- **IAM**: Least-privilege roles and policies

## Deployment

```bash
cd infrastructure
terraform init
terraform plan -var-file="environments/prod.tfvars"
terraform apply -var-file="environments/prod.tfvars"
```

## Sizing Guidelines

### Production Sizing (100k events/minute)
- **EKS Nodes**: 3x m5.2xlarge (min), 10x m5.4xlarge (max)
- **MSK**: 3x kafka.m5.xlarge brokers
- **Redis**: cache.r6g.xlarge
- **RDS**: db.r5.large for Airflow

### Cost Optimization
- Spot instances for non-critical workloads
- Auto-scaling based on metrics
- S3 intelligent tiering
- Reserved instances for baseline capacity
