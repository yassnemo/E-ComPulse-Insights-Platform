#!/bin/bash

# E-ComPulse Insights Platform - Cleanup Script
# This script helps clean up development/test resources to save costs

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ENVIRONMENT=${1:-development}
DRY_RUN=${2:-false}

echo -e "${BLUE}🧹 E-ComPulse Platform Cleanup${NC}"
echo "============================="
echo "Environment: $ENVIRONMENT"
echo "Dry run: $DRY_RUN"
echo "Timestamp: $(date)"
echo

# Function to confirm action
confirm_action() {
    local message=$1
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would execute: $message"
        return 0
    fi
    
    echo -e "${YELLOW}⚠️  $message${NC}"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipped."
        return 1
    fi
    return 0
}

# Function to cleanup Kubernetes resources
cleanup_kubernetes() {
    echo -e "${BLUE}☸️  Cleaning up Kubernetes resources${NC}"
    echo "-----------------------------------"
    
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl not found${NC}"
        return 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${YELLOW}⚠️  No Kubernetes cluster access - skipping K8s cleanup${NC}"
        return 0
    fi
    
    # Delete application namespaces based on environment
    local namespaces_to_delete=()
    
    case $ENVIRONMENT in
        development|dev)
            namespaces_to_delete=("ecompulse-dev" "monitoring-dev" "airflow-dev")
            ;;
        staging|stage)
            namespaces_to_delete=("ecompulse-staging" "monitoring-staging" "airflow-staging")
            ;;
        production|prod)
            echo -e "${RED}🚨 Production cleanup requires manual confirmation${NC}"
            confirm_action "Delete PRODUCTION Kubernetes resources" || return 0
            namespaces_to_delete=("ecompulse" "monitoring" "airflow")
            ;;
        test)
            namespaces_to_delete=("ecompulse-test" "monitoring-test" "airflow-test")
            ;;
        all)
            confirm_action "Delete ALL Kubernetes namespaces (very destructive)" || return 0
            namespaces_to_delete=($(kubectl get namespaces -o name | grep -E "(ecompulse|monitoring|airflow)" | cut -d'/' -f2))
            ;;
    esac
    
    # Delete namespaces
    for namespace in "${namespaces_to_delete[@]}"; do
        if kubectl get namespace "$namespace" &> /dev/null; then
            if confirm_action "Delete namespace '$namespace' and all its resources"; then
                echo "Deleting namespace: $namespace"
                if [[ "$DRY_RUN" != "true" ]]; then
                    kubectl delete namespace "$namespace" --timeout=300s &
                fi
            fi
        else
            echo "Namespace '$namespace' not found - skipping"
        fi
    done
    
    # Wait for background deletions
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "Waiting for namespace deletions to complete..."
        wait
    fi
    
    # Clean up persistent volumes
    if confirm_action "Delete unbound persistent volumes"; then
        local unbound_pvs=$(kubectl get pv --no-headers 2>/dev/null | grep -v "Bound" | awk '{print $1}' || true)
        if [[ -n "$unbound_pvs" ]]; then
            echo "Deleting unbound PVs: $unbound_pvs"
            if [[ "$DRY_RUN" != "true" ]]; then
                echo "$unbound_pvs" | xargs kubectl delete pv
            fi
        else
            echo "No unbound persistent volumes found"
        fi
    fi
    
    # Clean up completed/failed jobs
    if confirm_action "Delete completed and failed jobs"; then
        echo "Cleaning up completed/failed jobs..."
        if [[ "$DRY_RUN" != "true" ]]; then
            kubectl delete jobs --field-selector status.successful=1 -A 2>/dev/null || true
            kubectl delete jobs --field-selector status.failed=1 -A 2>/dev/null || true
        fi
    fi
    
    echo
}

# Function to cleanup Helm releases
cleanup_helm() {
    echo -e "${BLUE}⚓ Cleaning up Helm releases${NC}"
    echo "----------------------------"
    
    if ! command -v helm &> /dev/null; then
        echo -e "${YELLOW}⚠️  Helm not found - skipping Helm cleanup${NC}"
        return 0
    fi
    
    # Get releases based on environment
    local releases_to_delete=()
    
    case $ENVIRONMENT in
        development|dev)
            releases_to_delete=($(helm list -A -f ".*-dev$" -q 2>/dev/null || true))
            ;;
        staging|stage)
            releases_to_delete=($(helm list -A -f ".*-staging$" -q 2>/dev/null || true))
            ;;
        production|prod)
            echo -e "${RED}🚨 Production Helm cleanup requires manual confirmation${NC}"
            confirm_action "Delete PRODUCTION Helm releases" || return 0
            releases_to_delete=($(helm list -A -f "ecompulse.*" -q 2>/dev/null || true))
            ;;
        test)
            releases_to_delete=($(helm list -A -f ".*-test$" -q 2>/dev/null || true))
            ;;
        all)
            confirm_action "Delete ALL Helm releases (very destructive)" || return 0
            releases_to_delete=($(helm list -A -q 2>/dev/null || true))
            ;;
    esac
    
    # Delete releases
    for release in "${releases_to_delete[@]}"; do
        if [[ -n "$release" ]]; then
            if confirm_action "Delete Helm release '$release'"; then
                echo "Deleting Helm release: $release"
                if [[ "$DRY_RUN" != "true" ]]; then
                    helm uninstall "$release" --timeout=300s
                fi
            fi
        fi
    done
    
    echo
}

# Function to cleanup AWS resources
cleanup_aws() {
    echo -e "${BLUE}☁️  Cleaning up AWS resources${NC}"
    echo "-----------------------------"
    
    if ! command -v aws &> /dev/null; then
        echo -e "${YELLOW}⚠️  AWS CLI not found - skipping AWS cleanup${NC}"
        return 0
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${YELLOW}⚠️  AWS not configured - skipping AWS cleanup${NC}"
        return 0
    fi
    
    local region=$(aws configure get region || echo "us-west-2")
    
    case $ENVIRONMENT in
        development|dev)
            local cluster_name="ecompulse-eks-cluster-dev"
            local kafka_cluster_tag="Environment=development"
            ;;
        staging|stage)
            local cluster_name="ecompulse-eks-cluster-staging"
            local kafka_cluster_tag="Environment=staging"
            ;;
        production|prod)
            echo -e "${RED}🚨 Production AWS cleanup requires manual confirmation${NC}"
            confirm_action "Delete PRODUCTION AWS resources (EKS, MSK, RDS, etc.)" || return 0
            local cluster_name="ecompulse-eks-cluster"
            local kafka_cluster_tag="Environment=production"
            ;;
        test)
            local cluster_name="ecompulse-eks-cluster-test"
            local kafka_cluster_tag="Environment=test"
            ;;
    esac
    
    # Cleanup EKS cluster
    if aws eks describe-cluster --name "$cluster_name" --region "$region" &> /dev/null; then
        if confirm_action "Delete EKS cluster '$cluster_name'"; then
            echo "Deleting EKS cluster: $cluster_name"
            if [[ "$DRY_RUN" != "true" ]]; then
                aws eks delete-cluster --name "$cluster_name" --region "$region"
                echo "EKS cluster deletion initiated (takes 10-15 minutes)"
            fi
        fi
    else
        echo "EKS cluster '$cluster_name' not found"
    fi
    
    # Cleanup MSK clusters
    local kafka_clusters=$(aws kafka list-clusters --region "$region" --query "ClusterInfoList[?Tags.$kafka_cluster_tag].ClusterArn" --output text 2>/dev/null || true)
    if [[ -n "$kafka_clusters" ]]; then
        while IFS= read -r cluster_arn; do
            if [[ -n "$cluster_arn" ]]; then
                local cluster_name=$(aws kafka describe-cluster --cluster-arn "$cluster_arn" --query "ClusterInfo.ClusterName" --output text)
                if confirm_action "Delete MSK cluster '$cluster_name'"; then
                    echo "Deleting MSK cluster: $cluster_name"
                    if [[ "$DRY_RUN" != "true" ]]; then
                        aws kafka delete-cluster --cluster-arn "$cluster_arn" --region "$region"
                    fi
                fi
            fi
        done <<< "$kafka_clusters"
    else
        echo "No MSK clusters found for environment: $ENVIRONMENT"
    fi
    
    # Cleanup RDS instances
    local rds_instances=$(aws rds describe-db-instances --region "$region" --query "DBInstances[?contains(DBInstanceIdentifier, 'ecompulse') && contains(DBInstanceIdentifier, '$ENVIRONMENT')].DBInstanceIdentifier" --output text 2>/dev/null || true)
    if [[ -n "$rds_instances" ]]; then
        while IFS= read -r instance; do
            if [[ -n "$instance" ]]; then
                if confirm_action "Delete RDS instance '$instance'"; then
                    echo "Deleting RDS instance: $instance"
                    if [[ "$DRY_RUN" != "true" ]]; then
                        aws rds delete-db-instance --db-instance-identifier "$instance" --skip-final-snapshot --region "$region"
                    fi
                fi
            fi
        done <<< "$rds_instances"
    else
        echo "No RDS instances found for environment: $ENVIRONMENT"
    fi
    
    # Cleanup ElastiCache clusters
    local elasticache_clusters=$(aws elasticache describe-cache-clusters --region "$region" --query "CacheClusters[?contains(CacheClusterId, 'ecompulse') && contains(CacheClusterId, '$ENVIRONMENT')].CacheClusterId" --output text 2>/dev/null || true)
    if [[ -n "$elasticache_clusters" ]]; then
        while IFS= read -r cluster; do
            if [[ -n "$cluster" ]]; then
                if confirm_action "Delete ElastiCache cluster '$cluster'"; then
                    echo "Deleting ElastiCache cluster: $cluster"
                    if [[ "$DRY_RUN" != "true" ]]; then
                        aws elasticache delete-cache-cluster --cache-cluster-id "$cluster" --region "$region"
                    fi
                fi
            fi
        done <<< "$elasticache_clusters"
    else
        echo "No ElastiCache clusters found for environment: $ENVIRONMENT"
    fi
    
    echo
}

# Function to cleanup Docker resources
cleanup_docker() {
    echo -e "${BLUE}🐳 Cleaning up Docker resources${NC}"
    echo "------------------------------"
    
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}⚠️  Docker not found - skipping Docker cleanup${NC}"
        return 0
    fi
    
    if ! docker info &> /dev/null; then
        echo -e "${YELLOW}⚠️  Docker not running - skipping Docker cleanup${NC}"
        return 0
    fi
    
    # Clean up E-ComPulse related images
    local ecompulse_images=$(docker images --format "table {{.Repository}}:{{.Tag}}" | grep -i ecompulse || true)
    if [[ -n "$ecompulse_images" ]]; then
        if confirm_action "Delete E-ComPulse Docker images"; then
            echo "Deleting E-ComPulse images..."
            if [[ "$DRY_RUN" != "true" ]]; then
                docker images --format "{{.Repository}}:{{.Tag}}" | grep -i ecompulse | xargs docker rmi -f 2>/dev/null || true
            fi
        fi
    else
        echo "No E-ComPulse Docker images found"
    fi
    
    # Clean up dangling images
    local dangling_images=$(docker images -f "dangling=true" -q)
    if [[ -n "$dangling_images" ]]; then
        if confirm_action "Delete dangling Docker images"; then
            echo "Deleting dangling images..."
            if [[ "$DRY_RUN" != "true" ]]; then
                docker image prune -f
            fi
        fi
    else
        echo "No dangling Docker images found"
    fi
    
    # Clean up unused volumes
    local unused_volumes=$(docker volume ls -f "dangling=true" -q)
    if [[ -n "$unused_volumes" ]]; then
        if confirm_action "Delete unused Docker volumes"; then
            echo "Deleting unused volumes..."
            if [[ "$DRY_RUN" != "true" ]]; then
                docker volume prune -f
            fi
        fi
    else
        echo "No unused Docker volumes found"
    fi
    
    echo
}

# Function to cleanup local files
cleanup_local_files() {
    echo -e "${BLUE}📁 Cleaning up local files${NC}"
    echo "-------------------------"
    
    # Clean up temporary files
    local temp_files=(
        "terraform-outputs.txt"
        "terraform-outputs.json"
        "*.tfplan"
        "terraform.tfstate.backup"
        ".terraform.lock.hcl"
        "*.log"
        "*.tmp"
    )
    
    for pattern in "${temp_files[@]}"; do
        local files=$(find . -name "$pattern" -type f 2>/dev/null || true)
        if [[ -n "$files" ]]; then
            if confirm_action "Delete temporary files matching '$pattern'"; then
                echo "Deleting files: $files"
                if [[ "$DRY_RUN" != "true" ]]; then
                    find . -name "$pattern" -type f -delete 2>/dev/null || true
                fi
            fi
        fi
    done
    
    # Clean up Terraform state files (be careful!)
    if [[ "$ENVIRONMENT" != "production" && "$ENVIRONMENT" != "prod" ]]; then
        local terraform_state_files=$(find infrastructure/ -name "terraform.tfstate" -o -name ".terraform/" -type d 2>/dev/null || true)
        if [[ -n "$terraform_state_files" ]]; then
            if confirm_action "Delete Terraform state files (will require re-import for existing resources)"; then
                echo "Deleting Terraform state files..."
                if [[ "$DRY_RUN" != "true" ]]; then
                    find infrastructure/ -name "terraform.tfstate" -delete 2>/dev/null || true
                    find infrastructure/ -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
                fi
            fi
        fi
    fi
    
    echo
}

# Function to show cleanup summary
show_cleanup_summary() {
    echo -e "${BLUE}📋 Cleanup Summary${NC}"
    echo "=================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}This was a dry run. No actual resources were deleted.${NC}"
        echo "To perform actual cleanup, run without the 'dry-run' parameter:"
        echo "  $0 $ENVIRONMENT"
    else
        echo -e "${GREEN}Cleanup completed for environment: $ENVIRONMENT${NC}"
        echo
        echo "Resources that may still be terminating:"
        echo "- EKS cluster deletion (10-15 minutes)"
        echo "- RDS instance deletion (5-10 minutes)"
        echo "- MSK cluster deletion (5-10 minutes)"
        echo
        echo "Verify cleanup completion:"
        echo "- AWS Console: Check EKS, MSK, RDS, ElastiCache"
        echo "- kubectl: kubectl get all -A"
        echo "- Docker: docker images | grep ecompulse"
    fi
    
    echo
    echo "Cost savings tips:"
    echo "- Stop EC2 instances when not in use"
    echo "- Use spot instances for non-production workloads"
    echo "- Set up auto-scaling policies"
    echo "- Review AWS Cost Explorer for optimization opportunities"
}

# Main cleanup function
main() {
    case $ENVIRONMENT in
        development|dev|staging|stage|test|production|prod|all)
            echo "Proceeding with cleanup for environment: $ENVIRONMENT"
            ;;
        *)
            echo -e "${RED}❌ Invalid environment: $ENVIRONMENT${NC}"
            echo "Valid environments: development, staging, test, production, all"
            exit 1
            ;;
    esac
    
    if [[ "$ENVIRONMENT" == "production" || "$ENVIRONMENT" == "prod" ]]; then
        echo -e "${RED}🚨 WARNING: You are about to clean up PRODUCTION resources!${NC}"
        echo "This action is irreversible and will cause service downtime."
        echo
        confirm_action "Proceed with PRODUCTION cleanup" || exit 0
    fi
    
    cleanup_kubernetes
    cleanup_helm
    cleanup_aws
    cleanup_docker
    cleanup_local_files
    
    show_cleanup_summary
}

# Show help
show_help() {
    echo "E-ComPulse Platform Cleanup Script"
    echo "=================================="
    echo
    echo "Usage: $0 [environment] [dry-run]"
    echo
    echo "Environments:"
    echo "  development, dev    Clean up development resources"
    echo "  staging, stage      Clean up staging resources"
    echo "  test               Clean up test resources"
    echo "  production, prod    Clean up production resources (requires confirmation)"
    echo "  all                Clean up all environments (very destructive)"
    echo
    echo "Options:"
    echo "  dry-run            Show what would be deleted without actually deleting"
    echo
    echo "Examples:"
    echo "  $0 development              # Clean up development environment"
    echo "  $0 staging dry-run          # Show what would be cleaned in staging"
    echo "  $0 production               # Clean up production (with confirmations)"
    echo
    echo "This script will clean up:"
    echo "- Kubernetes namespaces and resources"
    echo "- Helm releases"
    echo "- AWS resources (EKS, MSK, RDS, ElastiCache)"
    echo "- Docker images and volumes"
    echo "- Local temporary files"
}

# Parse command line arguments
case "${1:-}" in
    --help|-h|help)
        show_help
        exit 0
        ;;
    "")
        echo -e "${RED}❌ Environment required${NC}"
        echo "Run '$0 --help' for usage information"
        exit 1
        ;;
esac

# Validate dry-run parameter
if [[ "${2:-}" == "dry-run" || "${2:-}" == "--dry-run" ]]; then
    DRY_RUN="true"
elif [[ -n "${2:-}" ]]; then
    echo -e "${RED}❌ Invalid parameter: $2${NC}"
    echo "Use 'dry-run' or leave empty"
    exit 1
fi

# Run main function
main
