#!/bin/bash

# E-ComPulse Insights Platform - Prerequisites Verification Script
# This script verifies that all required tools and configurations are in place

set -e

echo "🔍 E-ComPulse Prerequisites Verification"
echo "========================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track verification status
ERRORS=0
WARNINGS=0

# Function to check command existence
check_command() {
    local cmd=$1
    local min_version=$2
    local purpose=$3
    
    if command -v $cmd &> /dev/null; then
        local version=$($cmd --version 2>/dev/null | head -n1 || echo "unknown")
        echo -e "${GREEN}✓${NC} $cmd found: $version"
        if [[ ! -z "$purpose" ]]; then
            echo "  Purpose: $purpose"
        fi
    else
        echo -e "${RED}✗${NC} $cmd not found"
        echo "  Required for: $purpose"
        echo "  Install: https://docs.example.com/install-$cmd"
        ((ERRORS++))
    fi
    echo
}

# Function to check AWS configuration
check_aws_config() {
    echo "🔐 AWS Configuration"
    echo "-------------------"
    
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}✗${NC} AWS CLI not found"
        ((ERRORS++))
        return
    fi
    
    # Check AWS credentials
    if aws sts get-caller-identity &> /dev/null; then
        local account_id=$(aws sts get-caller-identity --query Account --output text)
        local user_arn=$(aws sts get-caller-identity --query Arn --output text)
        local region=$(aws configure get region || echo "not set")
        
        echo -e "${GREEN}✓${NC} AWS credentials configured"
        echo "  Account ID: $account_id"
        echo "  User/Role: $user_arn"
        echo "  Default Region: $region"
        
        if [[ "$region" == "not set" ]]; then
            echo -e "${YELLOW}⚠${NC} No default region set, using us-west-2"
            ((WARNINGS++))
        fi
    else
        echo -e "${RED}✗${NC} AWS credentials not configured or invalid"
        echo "  Run: aws configure"
        ((ERRORS++))
    fi
    echo
}

# Function to check Docker
check_docker() {
    echo "🐳 Docker Configuration"
    echo "----------------------"
    
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null; then
            local version=$(docker --version)
            local memory=$(docker system info --format '{{.MemTotal}}' 2>/dev/null || echo "unknown")
            echo -e "${GREEN}✓${NC} Docker is running: $version"
            echo "  Memory available: $memory"
            
            # Check if Docker has enough memory
            if [[ "$memory" != "unknown" ]] && [[ $memory -lt 8589934592 ]]; then
                echo -e "${YELLOW}⚠${NC} Docker memory < 8GB, may cause issues with heavy workloads"
                ((WARNINGS++))
            fi
        else
            echo -e "${RED}✗${NC} Docker is installed but not running"
            echo "  Start Docker Desktop or Docker daemon"
            ((ERRORS++))
        fi
    else
        echo -e "${RED}✗${NC} Docker not found"
        ((ERRORS++))
    fi
    echo
}

# Function to check Kubernetes access
check_kubernetes() {
    echo "☸️  Kubernetes Access"
    echo "--------------------"
    
    if command -v kubectl &> /dev/null; then
        if kubectl cluster-info &> /dev/null; then
            local context=$(kubectl config current-context)
            local cluster=$(kubectl config view --minify --output jsonpath='{.clusters[0].name}')
            local server=$(kubectl config view --minify --output jsonpath='{.clusters[0].cluster.server}')
            
            echo -e "${GREEN}✓${NC} Kubernetes cluster access configured"
            echo "  Current context: $context"
            echo "  Cluster: $cluster"
            echo "  Server: $server"
            
            # Check node status
            local nodes=$(kubectl get nodes --no-headers | wc -l)
            local ready_nodes=$(kubectl get nodes --no-headers | grep " Ready " | wc -l)
            echo "  Nodes: $ready_nodes/$nodes ready"
            
            if [[ $ready_nodes -lt $nodes ]]; then
                echo -e "${YELLOW}⚠${NC} Some nodes are not ready"
                ((WARNINGS++))
            fi
        else
            echo -e "${YELLOW}⚠${NC} kubectl configured but no cluster access"
            echo "  Run: aws eks update-kubeconfig --region us-west-2 --name ecompulse-eks-cluster"
            ((WARNINGS++))
        fi
    else
        echo -e "${RED}✗${NC} kubectl not found"
        ((ERRORS++))
    fi
    echo
}

# Function to check system resources
check_system_resources() {
    echo "💻 System Resources"
    echo "------------------"
    
    # Check available memory
    if command -v free &> /dev/null; then
        local memory_gb=$(free -g | awk '/^Mem:/{print $2}')
        if [[ $memory_gb -ge 16 ]]; then
            echo -e "${GREEN}✓${NC} Memory: ${memory_gb}GB (sufficient)"
        elif [[ $memory_gb -ge 8 ]]; then
            echo -e "${YELLOW}⚠${NC} Memory: ${memory_gb}GB (minimum, may be slow)"
            ((WARNINGS++))
        else
            echo -e "${RED}✗${NC} Memory: ${memory_gb}GB (insufficient, need 8GB+)"
            ((ERRORS++))
        fi
    elif command -v vm_stat &> /dev/null; then
        # macOS memory check
        local memory_gb=$(echo "$(vm_stat | grep "Pages free:" | awk '{print $3}' | tr -d .) * 4096 / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "unknown")
        echo "  Available Memory: ${memory_gb}GB"
    fi
    
    # Check available disk space
    local disk_gb=$(df -BG . | awk 'NR==2 {print $4}' | tr -d 'G' 2>/dev/null || echo "unknown")
    if [[ "$disk_gb" != "unknown" ]]; then
        if [[ $disk_gb -ge 100 ]]; then
            echo -e "${GREEN}✓${NC} Disk space: ${disk_gb}GB (sufficient)"
        elif [[ $disk_gb -ge 50 ]]; then
            echo -e "${YELLOW}⚠${NC} Disk space: ${disk_gb}GB (tight, monitor usage)"
            ((WARNINGS++))
        else
            echo -e "${RED}✗${NC} Disk space: ${disk_gb}GB (insufficient, need 50GB+)"
            ((ERRORS++))
        fi
    fi
    echo
}

# Function to check AWS service quotas
check_aws_quotas() {
    echo "📊 AWS Service Quotas"
    echo "--------------------"
    
    if ! command -v aws &> /dev/null || ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${YELLOW}⚠${NC} Skipping quota check (AWS not configured)"
        return
    fi
    
    local region=$(aws configure get region || echo "us-west-2")
    
    # Check EKS quota
    local eks_quota=$(aws service-quotas get-service-quota --service-code eks --quota-code L-1194D53C --region $region --query 'Quota.Value' --output text 2>/dev/null || echo "unknown")
    if [[ "$eks_quota" != "unknown" ]] && [[ $(echo "$eks_quota >= 1" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
        echo -e "${GREEN}✓${NC} EKS clusters quota: $eks_quota"
    else
        echo -e "${YELLOW}⚠${NC} Could not verify EKS quota"
        ((WARNINGS++))
    fi
    
    # Check EC2 quota
    local ec2_quota=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A --region $region --query 'Quota.Value' --output text 2>/dev/null || echo "unknown")
    if [[ "$ec2_quota" != "unknown" ]]; then
        echo -e "${GREEN}✓${NC} EC2 instances quota: $ec2_quota"
    else
        echo -e "${YELLOW}⚠${NC} Could not verify EC2 quota"
        ((WARNINGS++))
    fi
    echo
}

# Main verification process
echo "Starting prerequisites verification..."
echo

# Check core tools
echo "🛠️  Core Tools"
echo "-------------"
check_command "terraform" "1.5.0" "Infrastructure as Code deployment"
check_command "kubectl" "1.27" "Kubernetes cluster management"
check_command "helm" "3.12" "Kubernetes package management"
check_command "aws" "2.13" "AWS resource management"
check_command "git" "2.0" "Source code management"
check_command "curl" "7.0" "HTTP requests and downloads"
check_command "jq" "1.6" "JSON processing and queries"

# Check optional but useful tools
echo "🔧 Optional Tools"
echo "----------------"
check_command "yq" "4.0" "YAML processing (helpful for configs)"
check_command "bc" "1.0" "Mathematical calculations (scripts)"
check_command "unzip" "6.0" "Archive extraction"

# Run specific checks
check_aws_config
check_docker
check_kubernetes
check_system_resources
check_aws_quotas

# Check project structure
echo "📁 Project Structure"
echo "-------------------"
if [[ -f "infrastructure/main.tf" ]]; then
    echo -e "${GREEN}✓${NC} Terraform infrastructure code found"
else
    echo -e "${RED}✗${NC} Terraform infrastructure code not found"
    ((ERRORS++))
fi

if [[ -f "scripts/deploy.sh" ]]; then
    echo -e "${GREEN}✓${NC} Deployment script found"
else
    echo -e "${RED}✗${NC} Deployment script not found"
    ((ERRORS++))
fi

if [[ -d "k8s/helm/ecompulse-platform" ]]; then
    echo -e "${GREEN}✓${NC} Helm charts found"
else
    echo -e "${RED}✗${NC} Helm charts not found"
    ((ERRORS++))
fi
echo

# Summary
echo "📋 Verification Summary"
echo "======================"
if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✅ All prerequisites verified successfully!${NC}"
    echo "You're ready to deploy the E-ComPulse Insights Platform."
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}⚠️  Prerequisites mostly satisfied with $WARNINGS warning(s)${NC}"
    echo "You can proceed with deployment, but review the warnings above."
else
    echo -e "${RED}❌ Prerequisites verification failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo "Please resolve the errors above before proceeding with deployment."
    exit 1
fi

echo
echo "Next steps:"
echo "1. Review any warnings or errors above"
echo "2. Run: ./scripts/deploy.sh [environment]"
echo "3. Monitor deployment: kubectl get pods -A"
echo "4. Access dashboards once deployment completes"
