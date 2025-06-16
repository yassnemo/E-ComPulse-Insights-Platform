# Kubernetes Manifests for E-ComPulse Insights Platform

This directory contains Kubernetes manifests and Helm charts for deploying the E-ComPulse Insights Platform on Amazon EKS.

## 📁 Directory Structure

```
k8s/
├── README.md                     # This file
├── helm/                         # Helm charts
│   ├── ecompulse-platform/      # Main platform chart
│   ├── kafka/                   # Kafka configuration
│   ├── spark/                   # Spark Streaming jobs
│   ├── airflow/                 # Apache Airflow
│   └── monitoring/              # Prometheus & Grafana
├── manifests/                   # Raw Kubernetes YAML
│   ├── namespaces/             # Namespace definitions
│   ├── configmaps/             # Configuration maps
│   ├── secrets/                # Secret templates
│   ├── deployments/            # Application deployments
│   ├── services/               # Service definitions
│   └── ingress/                # Ingress controllers
└── scripts/                    # Deployment scripts
    ├── deploy.sh               # Main deployment script
    ├── setup-cluster.sh        # Cluster setup
    └── cleanup.sh              # Environment cleanup
```

## 🚀 Quick Start

### Prerequisites

1. **AWS CLI** configured with appropriate permissions
2. **kubectl** installed and configured
3. **Helm 3.x** installed
4. **Amazon EKS cluster** provisioned (via Terraform)

### Deployment Steps

1. **Setup the cluster and install necessary components:**
   ```bash
   ./scripts/setup-cluster.sh
   ```

2. **Deploy the platform:**
   ```bash
   ./scripts/deploy.sh production
   ```

3. **Verify deployment:**
   ```bash
   kubectl get pods -n ecompulse
   kubectl get services -n ecompulse
   ```

## 📊 Monitoring & Observability

### Prometheus Metrics

The platform exposes the following metrics:

- **Kafka Metrics**: Topic throughput, consumer lag, broker health
- **Spark Metrics**: Job duration, processing rates, error counts  
- **Application Metrics**: Custom business metrics from synthetic generator
- **Infrastructure Metrics**: CPU, memory, network, disk usage

### Grafana Dashboards

Pre-configured dashboards available:

- **Platform Overview**: High-level system health
- **Kafka Dashboard**: Message queues and throughput
- **Spark Streaming**: Real-time processing metrics
- **Business Analytics**: E-commerce KPIs and trends

### Accessing Monitoring

```bash
# Port-forward Grafana
kubectl port-forward svc/grafana 3000:3000 -n monitoring

# Port-forward Prometheus  
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
```

## 🔧 Configuration

### Environment-Specific Values

Create environment-specific value files:

```bash
# Development
helm/ecompulse-platform/values-dev.yaml

# Staging  
helm/ecompulse-platform/values-staging.yaml

# Production
helm/ecompulse-platform/values-prod.yaml
```

### Custom Configuration

Override default values by creating a custom `values.yaml`:

```yaml
# Custom resource limits
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi" 
    cpu: "2000m"

# Scaling configuration
replicaCount: 3
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

## 🔒 Security

### RBAC Configuration

The platform includes comprehensive RBAC policies:

- **Service Accounts**: Dedicated accounts for each component
- **Roles & RoleBindings**: Minimal required permissions
- **Network Policies**: Pod-to-pod communication restrictions
- **Pod Security Standards**: Enforced security contexts

### Secrets Management

Secrets are managed through:

- **Kubernetes Secrets**: For database credentials, API keys
- **AWS Secrets Manager**: For external service credentials
- **External Secrets Operator**: Automated secret synchronization

## 📈 Scaling

### Horizontal Pod Autoscaling (HPA)

Automatic scaling based on:
- CPU utilization (70% threshold)
- Memory utilization (80% threshold)  
- Custom metrics (Kafka consumer lag)

### Vertical Pod Autoscaling (VPA)

Resource request optimization:
- Automatic resource recommendation
- Historical usage analysis
- Cost optimization

### Cluster Autoscaling

EKS cluster auto-scaling:
- Node group scaling based on pod resource requests
- Spot instance integration for cost optimization
- Multi-AZ deployment for high availability

## 🛠️ Troubleshooting

### Common Issues

1. **Pod Startup Issues**:
   ```bash
   kubectl describe pod <pod-name> -n ecompulse
   kubectl logs <pod-name> -n ecompulse
   ```

2. **Service Connectivity**:
   ```bash
   kubectl get endpoints -n ecompulse
   kubectl run debug --image=nicolaka/netshoot -n ecompulse
   ```

3. **Resource Constraints**:
   ```bash
   kubectl top pods -n ecompulse
   kubectl get events -n ecompulse --sort-by='.lastTimestamp'
   ```

### Performance Tuning

1. **JVM Settings** for Spark/Kafka:
   ```yaml
   env:
     - name: JAVA_OPTS
       value: "-Xmx2g -XX:+UseG1GC -XX:G1HeapRegionSize=16m"
   ```

2. **Resource Allocation**:
   ```yaml
   resources:
     requests:
       memory: "1Gi"
       cpu: "500m"
     limits:
       memory: "2Gi"
       cpu: "1000m"
   ```

## 🔄 CI/CD Integration

### GitOps Workflow

The platform supports GitOps deployment via:

- **ArgoCD**: Declarative GitOps continuous delivery
- **Flux**: Progressive delivery and canary deployments
- **GitHub Actions**: Automated testing and deployment pipelines

### Deployment Strategies

1. **Blue-Green Deployment**
2. **Canary Releases**
3. **Rolling Updates**
4. **Feature Toggles**

## 📋 Maintenance

### Regular Tasks

1. **Update Dependencies**:
   ```bash
   helm dependency update helm/ecompulse-platform
   ```

2. **Backup Configuration**:
   ```bash
   kubectl get configmaps -o yaml > backup-configmaps.yaml
   ```

3. **Security Scanning**:
   ```bash
   trivy image <image-name>
   ```

### Disaster Recovery

1. **ETCD Backup**: Automated via Velero
2. **Persistent Volume Snapshots**: EBS snapshot automation
3. **Configuration Backup**: GitOps repository as source of truth

## 📞 Support

For deployment issues and questions:
- 📧 **Email**: k8s-support@ecompulse.com
- 📚 **Documentation**: https://docs.ecompulse.com/k8s
- 🔧 **Runbooks**: `/docs/runbooks/`
