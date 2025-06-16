#!/bin/bash

# E-ComPulse Insights Platform - Complete Deployment Script
# This script orchestrates the deployment of the entire platform

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${1:-"production"}
AWS_REGION=${AWS_REGION:-"us-west-2"}
CLUSTER_NAME="ecompulse-eks-cluster"
NAMESPACE="ecompulse"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
TERRAFORM_DIR="${PROJECT_ROOT}/infrastructure"
K8S_DIR="${PROJECT_ROOT}/k8s"
MONITORING_DIR="${PROJECT_ROOT}/monitoring"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required tools
    local tools=("aws" "kubectl" "helm" "terraform" "docker")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured properly"
        exit 1
    fi
    
    # Check kubectl configuration
    if ! kubectl version --client &> /dev/null; then
        log_error "kubectl not configured properly"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd "${TERRAFORM_DIR}"
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    terraform plan -var-file="environments/${ENVIRONMENT}.tfvars" -out=tfplan
    
    # Apply deployment
    terraform apply tfplan
    
    # Get outputs
    local cluster_endpoint=$(terraform output -raw cluster_endpoint)
    local cluster_name=$(terraform output -raw cluster_name)
    
    log_success "Infrastructure deployed successfully"
    
    # Update kubeconfig
    log_info "Updating kubeconfig..."
    aws eks update-kubeconfig --region "${AWS_REGION}" --name "${cluster_name}"
    
    cd - > /dev/null
}

setup_kubernetes() {
    log_info "Setting up Kubernetes components..."
    
    # Create namespace
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    # Label namespace
    kubectl label namespace "${NAMESPACE}" name="${NAMESPACE}" --overwrite
    
    # Setup RBAC
    kubectl apply -f "${K8S_DIR}/manifests/rbac/"
    
    # Setup ConfigMaps and Secrets
    kubectl apply -f "${K8S_DIR}/manifests/configmaps/" -n "${NAMESPACE}"
    kubectl apply -f "${K8S_DIR}/manifests/secrets/" -n "${NAMESPACE}"
    
    log_success "Kubernetes setup completed"
}

install_helm_charts() {
    log_info "Installing Helm charts..."
    
    # Add Helm repositories
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo add strimzi https://strimzi.io/charts/
    helm repo update
    
    # Install platform chart
    helm upgrade --install ecompulse-platform \
        "${K8S_DIR}/helm/ecompulse-platform" \
        --namespace "${NAMESPACE}" \
        --values "${K8S_DIR}/helm/ecompulse-platform/values-${ENVIRONMENT}.yaml" \
        --wait \
        --timeout=600s
    
    log_success "Helm charts installed successfully"
}

deploy_monitoring() {
    log_info "Deploying monitoring stack..."
    
    # Create monitoring namespace
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Prometheus
    helm upgrade --install prometheus prometheus-community/prometheus \
        --namespace monitoring \
        --values "${MONITORING_DIR}/prometheus/values.yaml" \
        --wait
    
    # Install Grafana
    helm upgrade --install grafana grafana/grafana \
        --namespace monitoring \
        --values "${MONITORING_DIR}/grafana/values.yaml" \
        --wait
    
    # Apply custom dashboards
    kubectl apply -f "${MONITORING_DIR}/grafana/dashboards/" -n monitoring
    
    log_success "Monitoring stack deployed successfully"
}

deploy_applications() {
    log_info "Deploying application components..."
    
    # Build and push Docker images
    local ecr_registry=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${AWS_REGION}.amazonaws.com
    
    # Login to ECR
    aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ecr_registry}"
    
    # Build synthetic generator
    log_info "Building synthetic generator..."
    cd "${PROJECT_ROOT}/data-ingestion/synthetic-generator"
    docker build -t "${ecr_registry}/ecompulse/synthetic-generator:latest" .
    docker push "${ecr_registry}/ecompulse/synthetic-generator:latest"
    cd - > /dev/null
    
    # Build Spark streaming jobs
    log_info "Building Spark streaming jobs..."
    cd "${PROJECT_ROOT}/spark-streaming"
    ./build.sh
    docker build -t "${ecr_registry}/ecompulse/spark-enrichment:latest" .
    docker push "${ecr_registry}/ecompulse/spark-enrichment:latest"
    cd - > /dev/null
    
    # Deploy applications
    kubectl apply -f "${K8S_DIR}/manifests/deployments/" -n "${NAMESPACE}"
    kubectl apply -f "${K8S_DIR}/manifests/services/" -n "${NAMESPACE}"
    
    log_success "Applications deployed successfully"
}

setup_ingress() {
    log_info "Setting up ingress controllers..."
    
    # Install NGINX Ingress Controller
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --set controller.service.type=LoadBalancer \
        --wait
    
    # Apply ingress rules
    kubectl apply -f "${K8S_DIR}/manifests/ingress/" -n "${NAMESPACE}"
    
    log_success "Ingress setup completed"
}

configure_autoscaling() {
    log_info "Configuring autoscaling..."
    
    # Install metrics server if not present
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    
    # Wait for metrics server
    kubectl wait --for=condition=available deployment/metrics-server -n kube-system --timeout=300s
    
    # Apply HPA configurations
    kubectl apply -f "${K8S_DIR}/manifests/hpa/" -n "${NAMESPACE}"
    
    # Apply VPA configurations (if enabled)
    if [ -d "${K8S_DIR}/manifests/vpa/" ]; then
        kubectl apply -f "${K8S_DIR}/manifests/vpa/" -n "${NAMESPACE}"
    fi
    
    log_success "Autoscaling configured successfully"
}

setup_data_sources() {
    log_info "Setting up data sources..."
    
    # Create Kafka topics
    kubectl exec -it kafka-0 -n "${NAMESPACE}" -- /opt/bitnami/kafka/bin/kafka-topics.sh \
        --create --topic ecommerce-events \
        --bootstrap-server localhost:9092 \
        --partitions 10 \
        --replication-factor 3
    
    kubectl exec -it kafka-0 -n "${NAMESPACE}" -- /opt/bitnami/kafka/bin/kafka-topics.sh \
        --create --topic enriched-events \
        --bootstrap-server localhost:9092 \
        --partitions 10 \
        --replication-factor 3
    
    kubectl exec -it kafka-0 -n "${NAMESPACE}" -- /opt/bitnami/kafka/bin/kafka-topics.sh \
        --create --topic session-analytics \
        --bootstrap-server localhost:9092 \
        --partitions 5 \
        --replication-factor 3
    
    log_success "Data sources setup completed"
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check pod status
    kubectl get pods -n "${NAMESPACE}"
    kubectl get pods -n monitoring
    
    # Check services
    kubectl get services -n "${NAMESPACE}"
    
    # Check ingress
    kubectl get ingress -n "${NAMESPACE}"
    
    # Check HPA
    kubectl get hpa -n "${NAMESPACE}"
    
    # Wait for all pods to be ready
    log_info "Waiting for all pods to be ready..."
    kubectl wait --for=condition=ready pod --all -n "${NAMESPACE}" --timeout=600s
    kubectl wait --for=condition=ready pod --all -n monitoring --timeout=600s
    
    # Run health checks
    log_info "Running health checks..."
    
    # Check synthetic generator
    if kubectl get deployment synthetic-generator -n "${NAMESPACE}" &> /dev/null; then
        local generator_status=$(kubectl get deployment synthetic-generator -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}')
        if [ "${generator_status}" -gt 0 ]; then
            log_success "Synthetic generator is running"
        else
            log_warning "Synthetic generator is not ready"
        fi
    fi
    
    # Check Kafka
    if kubectl get statefulset kafka -n "${NAMESPACE}" &> /dev/null; then
        local kafka_status=$(kubectl get statefulset kafka -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}')
        if [ "${kafka_status}" -gt 0 ]; then
            log_success "Kafka is running"
        else
            log_warning "Kafka is not ready"
        fi
    fi
    
    # Check Prometheus
    if kubectl get deployment prometheus-server -n monitoring &> /dev/null; then
        local prometheus_status=$(kubectl get deployment prometheus-server -n monitoring -o jsonpath='{.status.readyReplicas}')
        if [ "${prometheus_status}" -gt 0 ]; then
            log_success "Prometheus is running"
        else
            log_warning "Prometheus is not ready"
        fi
    fi
    
    # Check Grafana
    if kubectl get deployment grafana -n monitoring &> /dev/null; then
        local grafana_status=$(kubectl get deployment grafana -n monitoring -o jsonpath='{.status.readyReplicas}')
        if [ "${grafana_status}" -gt 0 ]; then
            log_success "Grafana is running"
        else
            log_warning "Grafana is not ready"
        fi
    fi
    
    log_success "Deployment verification completed"
}

print_access_info() {
    log_info "Getting access information..."
    
    # Get LoadBalancer IPs
    local ingress_ip=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    echo ""
    echo "================================="
    echo "E-ComPulse Platform Access Info"
    echo "================================="
    echo ""
    echo "Environment: ${ENVIRONMENT}"
    echo "Namespace: ${NAMESPACE}"
    echo ""
    
    if [ -n "${ingress_ip}" ]; then
        echo "Platform Endpoints:"
        echo "  - API Gateway: http://${ingress_ip}"
        echo "  - Grafana: http://${ingress_ip}/grafana"
        echo "  - Prometheus: http://${ingress_ip}/prometheus"
        echo ""
    fi
    
    echo "Port Forward Commands:"
    echo "  - Grafana: kubectl port-forward svc/grafana 3000:3000 -n monitoring"
    echo "  - Prometheus: kubectl port-forward svc/prometheus-server 9090:9090 -n monitoring"
    echo "  - Kafka UI: kubectl port-forward svc/kafka-ui 8080:8080 -n ${NAMESPACE}"
    echo ""
    
    echo "Grafana Login:"
    local grafana_password=$(kubectl get secret grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 --decode)
    echo "  - Username: admin"
    echo "  - Password: ${grafana_password}"
    echo ""
    
    echo "Useful Commands:"
    echo "  - View logs: kubectl logs -f deployment/synthetic-generator -n ${NAMESPACE}"
    echo "  - Scale deployment: kubectl scale deployment synthetic-generator --replicas=3 -n ${NAMESPACE}"
    echo "  - Check HPA: kubectl get hpa -n ${NAMESPACE}"
    echo ""
}

cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed with exit code: $exit_code"
        log_info "You can check the status with:"
        echo "  kubectl get pods -n ${NAMESPACE}"
        echo "  kubectl logs -f deployment/synthetic-generator -n ${NAMESPACE}"
        echo "  kubectl describe pod <pod-name> -n ${NAMESPACE}"
    fi
    exit $exit_code
}

# Main deployment flow
main() {
    log_info "Starting E-ComPulse Insights Platform deployment..."
    log_info "Environment: ${ENVIRONMENT}"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "Cluster: ${CLUSTER_NAME}"
    log_info "Namespace: ${NAMESPACE}"
    echo ""
    
    # Set error handler
    trap cleanup_on_error ERR
    
    # Check prerequisites
    check_prerequisites
    
    # Deploy infrastructure
    deploy_infrastructure
    
    # Setup Kubernetes
    setup_kubernetes
    
    # Install Helm charts
    install_helm_charts
    
    # Deploy monitoring
    deploy_monitoring
    
    # Deploy applications
    deploy_applications
    
    # Setup ingress
    setup_ingress
    
    # Configure autoscaling
    configure_autoscaling
    
    # Setup data sources
    setup_data_sources
    
    # Verify deployment
    verify_deployment
    
    # Print access information
    print_access_info
    
    log_success "E-ComPulse Insights Platform deployment completed successfully!"
}

# Help function
show_help() {
    echo "Usage: $0 [ENVIRONMENT]"
    echo ""
    echo "Deploy the E-ComPulse Insights Platform"
    echo ""
    echo "Arguments:"
    echo "  ENVIRONMENT    Deployment environment (default: production)"
    echo "                 Options: development, staging, production"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_REGION     AWS region (default: us-west-2)"
    echo ""
    echo "Examples:"
    echo "  $0 production"
    echo "  AWS_REGION=us-east-1 $0 staging"
    echo ""
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    development|staging|production)
        main
        ;;
    "")
        main
        ;;
    *)
        log_error "Invalid environment: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
