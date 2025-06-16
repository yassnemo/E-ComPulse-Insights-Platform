#!/bin/bash

# E-ComPulse Insights Platform - Health Check Script
# This script performs comprehensive health checks on all platform components

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE_ECOMPULSE="ecompulse"
NAMESPACE_MONITORING="monitoring"
NAMESPACE_AIRFLOW="airflow"

# Track health status
HEALTHY=0
WARNINGS=0
CRITICAL=0

echo -e "${BLUE}🏥 E-ComPulse Platform Health Check${NC}"
echo "=================================="
echo "Timestamp: $(date)"
echo

# Function to check if kubectl is available and configured
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl not found${NC}"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Kubernetes cluster connection verified${NC}"
    echo
}

# Function to check namespace existence
check_namespace() {
    local ns=$1
    if kubectl get namespace $ns &> /dev/null; then
        echo -e "${GREEN}✅ Namespace '$ns' exists${NC}"
    else
        echo -e "${RED}❌ Namespace '$ns' not found${NC}"
        ((CRITICAL++))
    fi
}

# Function to check pod health
check_pods() {
    local namespace=$1
    local component=$2
    
    echo -e "${BLUE}🔍 Checking $component pods in namespace '$namespace'${NC}"
    
    if ! kubectl get namespace $namespace &> /dev/null; then
        echo -e "${RED}❌ Namespace '$namespace' not found${NC}"
        ((CRITICAL++))
        return
    fi
    
    local total_pods=$(kubectl get pods -n $namespace --no-headers 2>/dev/null | wc -l)
    local running_pods=$(kubectl get pods -n $namespace --no-headers 2>/dev/null | grep "Running" | wc -l)
    local ready_pods=$(kubectl get pods -n $namespace --no-headers 2>/dev/null | awk '$2 ~ /^[0-9]+\/[0-9]+$/ && $2 !~ /0\// {split($2,a,"/"); if(a[1]==a[2]) print}' | wc -l)
    
    echo "  Total pods: $total_pods"
    echo "  Running pods: $running_pods"
    echo "  Ready pods: $ready_pods"
    
    if [[ $total_pods -eq 0 ]]; then
        echo -e "${RED}❌ No pods found in namespace '$namespace'${NC}"
        ((CRITICAL++))
    elif [[ $running_pods -eq $total_pods && $ready_pods -eq $total_pods ]]; then
        echo -e "${GREEN}✅ All pods healthy${NC}"
        ((HEALTHY++))
    elif [[ $running_pods -eq $total_pods ]]; then
        echo -e "${YELLOW}⚠️  All pods running but some not ready${NC}"
        ((WARNINGS++))
    else
        echo -e "${RED}❌ Some pods not running${NC}"
        # Show problematic pods
        kubectl get pods -n $namespace | grep -v "Running\|Completed" || true
        ((CRITICAL++))
    fi
    
    # Check for recent restarts
    local restarted_pods=$(kubectl get pods -n $namespace --no-headers 2>/dev/null | awk '$4 > 0 {print $1, $4}')
    if [[ -n "$restarted_pods" ]]; then
        echo -e "${YELLOW}⚠️  Pods with restarts:${NC}"
        echo "$restarted_pods"
        ((WARNINGS++))
    fi
    
    echo
}

# Function to check services
check_services() {
    local namespace=$1
    local component=$2
    
    echo -e "${BLUE}🔍 Checking $component services in namespace '$namespace'${NC}"
    
    local services=$(kubectl get services -n $namespace --no-headers 2>/dev/null | wc -l)
    echo "  Total services: $services"
    
    if [[ $services -gt 0 ]]; then
        echo -e "${GREEN}✅ Services configured${NC}"
        
        # Check for services without endpoints
        local services_without_endpoints=0
        while IFS= read -r service; do
            if [[ -n "$service" ]]; then
                local endpoints=$(kubectl get endpoints $service -n $namespace -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
                if [[ $endpoints -eq 0 ]]; then
                    echo -e "${YELLOW}⚠️  Service '$service' has no endpoints${NC}"
                    ((services_without_endpoints++))
                fi
            fi
        done < <(kubectl get services -n $namespace --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
        
        if [[ $services_without_endpoints -gt 0 ]]; then
            ((WARNINGS++))
        fi
    else
        echo -e "${YELLOW}⚠️  No services found${NC}"
        ((WARNINGS++))
    fi
    
    echo
}

# Function to check persistent volumes
check_storage() {
    echo -e "${BLUE}🔍 Checking storage (PVs and PVCs)${NC}"
    
    local total_pvs=$(kubectl get pv --no-headers 2>/dev/null | wc -l)
    local bound_pvs=$(kubectl get pv --no-headers 2>/dev/null | grep "Bound" | wc -l)
    
    echo "  Total PVs: $total_pvs"
    echo "  Bound PVs: $bound_pvs"
    
    if [[ $total_pvs -gt 0 ]]; then
        if [[ $bound_pvs -eq $total_pvs ]]; then
            echo -e "${GREEN}✅ All persistent volumes bound${NC}"
        else
            echo -e "${YELLOW}⚠️  Some persistent volumes not bound${NC}"
            kubectl get pv | grep -v "Bound" || true
            ((WARNINGS++))
        fi
    fi
    
    # Check PVCs across namespaces
    local pending_pvcs=$(kubectl get pvc -A --no-headers 2>/dev/null | grep "Pending" | wc -l)
    if [[ $pending_pvcs -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  $pending_pvcs PVCs in Pending state${NC}"
        kubectl get pvc -A | grep "Pending" || true
        ((WARNINGS++))
    fi
    
    echo
}

# Function to check ingress controllers
check_ingress() {
    echo -e "${BLUE}🔍 Checking ingress controllers${NC}"
    
    local ingress_controllers=$(kubectl get pods -A --no-headers 2>/dev/null | grep -E "(ingress|nginx|traefik)" | wc -l)
    local running_controllers=$(kubectl get pods -A --no-headers 2>/dev/null | grep -E "(ingress|nginx|traefik)" | grep "Running" | wc -l)
    
    if [[ $ingress_controllers -gt 0 ]]; then
        echo "  Ingress controller pods: $running_controllers/$ingress_controllers running"
        if [[ $running_controllers -eq $ingress_controllers ]]; then
            echo -e "${GREEN}✅ Ingress controllers healthy${NC}"
        else
            echo -e "${RED}❌ Some ingress controllers not running${NC}"
            ((CRITICAL++))
        fi
        
        # Check ingress resources
        local ingress_resources=$(kubectl get ingress -A --no-headers 2>/dev/null | wc -l)
        echo "  Ingress resources: $ingress_resources"
    else
        echo -e "${YELLOW}⚠️  No ingress controllers found${NC}"
        ((WARNINGS++))
    fi
    
    echo
}

# Function to check node health
check_nodes() {
    echo -e "${BLUE}🔍 Checking node health${NC}"
    
    local total_nodes=$(kubectl get nodes --no-headers | wc -l)
    local ready_nodes=$(kubectl get nodes --no-headers | grep " Ready " | wc -l)
    
    echo "  Total nodes: $total_nodes"
    echo "  Ready nodes: $ready_nodes"
    
    if [[ $ready_nodes -eq $total_nodes ]]; then
        echo -e "${GREEN}✅ All nodes ready${NC}"
    else
        echo -e "${RED}❌ Some nodes not ready${NC}"
        kubectl get nodes | grep -v " Ready " || true
        ((CRITICAL++))
    fi
    
    # Check node resource usage
    echo "  Node resource usage:"
    kubectl top nodes 2>/dev/null || echo "    (metrics-server not available)"
    
    echo
}

# Function to check critical deployments
check_critical_deployments() {
    echo -e "${BLUE}🔍 Checking critical deployments${NC}"
    
    local deployments=(
        "kafka-cluster:$NAMESPACE_ECOMPULSE"
        "redis:$NAMESPACE_ECOMPULSE"
        "synthetic-generator:$NAMESPACE_ECOMPULSE"
        "spark-event-enrichment:$NAMESPACE_ECOMPULSE"
        "prometheus:$NAMESPACE_MONITORING"
        "grafana:$NAMESPACE_MONITORING"
        "airflow-webserver:$NAMESPACE_AIRFLOW"
    )
    
    for deployment_info in "${deployments[@]}"; do
        IFS=':' read -r deployment namespace <<< "$deployment_info"
        
        if kubectl get deployment $deployment -n $namespace &> /dev/null; then
            local replicas=$(kubectl get deployment $deployment -n $namespace -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
            local ready_replicas=$(kubectl get deployment $deployment -n $namespace -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            
            if [[ $ready_replicas -eq $replicas ]] && [[ $replicas -gt 0 ]]; then
                echo -e "${GREEN}✅ $deployment ($namespace): $ready_replicas/$replicas ready${NC}"
            else
                echo -e "${RED}❌ $deployment ($namespace): $ready_replicas/$replicas ready${NC}"
                ((CRITICAL++))
            fi
        else
            echo -e "${YELLOW}⚠️  $deployment not found in namespace $namespace${NC}"
            ((WARNINGS++))
        fi
    done
    
    echo
}

# Function to check external connectivity
check_external_connectivity() {
    echo -e "${BLUE}🔍 Checking external connectivity${NC}"
    
    # Test from a temporary pod
    kubectl run connectivity-test --image=busybox --rm -i --restart=Never --timeout=30s -- /bin/sh -c "
        echo 'Testing DNS resolution...'
        nslookup kubernetes.default.svc.cluster.local > /dev/null 2>&1 && echo 'DNS: OK' || echo 'DNS: FAILED'
        
        echo 'Testing internet connectivity...'
        wget -q --spider https://www.google.com > /dev/null 2>&1 && echo 'Internet: OK' || echo 'Internet: FAILED'
        
        echo 'Testing AWS API connectivity...'
        wget -q --spider https://eks.us-west-2.amazonaws.com > /dev/null 2>&1 && echo 'AWS API: OK' || echo 'AWS API: FAILED'
    " 2>/dev/null || echo -e "${YELLOW}⚠️  Could not run connectivity test${NC}"
    
    echo
}

# Function to check resource usage
check_resource_usage() {
    echo -e "${BLUE}🔍 Checking cluster resource usage${NC}"
    
    # Check if metrics-server is available
    if kubectl top nodes &> /dev/null; then
        echo "Cluster resource usage:"
        kubectl top nodes
        echo
        
        echo "Pod resource usage (top 10):"
        kubectl top pods -A --sort-by=memory | head -11
        
        # Check for resource-intensive pods
        local high_cpu_pods=$(kubectl top pods -A --no-headers 2>/dev/null | awk '$3 ~ /[0-9]+m/ && $3+0 > 1000 {print $1":"$2}' | wc -l)
        local high_memory_pods=$(kubectl top pods -A --no-headers 2>/dev/null | awk '$4 ~ /[0-9]+Mi/ && $4+0 > 1000 {print $1":"$2}' | wc -l)
        
        if [[ $high_cpu_pods -gt 0 ]]; then
            echo -e "${YELLOW}⚠️  $high_cpu_pods pods using >1000m CPU${NC}"
            ((WARNINGS++))
        fi
        
        if [[ $high_memory_pods -gt 0 ]]; then
            echo -e "${YELLOW}⚠️  $high_memory_pods pods using >1000Mi memory${NC}"
            ((WARNINGS++))
        fi
    else
        echo -e "${YELLOW}⚠️  Metrics server not available - cannot check resource usage${NC}"
        ((WARNINGS++))
    fi
    
    echo
}

# Function to check recent events
check_recent_events() {
    echo -e "${BLUE}🔍 Checking recent cluster events${NC}"
    
    local warning_events=$(kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' | tail -10)
    if [[ -n "$warning_events" && "$warning_events" != *"No resources found"* ]]; then
        echo -e "${YELLOW}⚠️  Recent warning events:${NC}"
        echo "$warning_events"
        ((WARNINGS++))
    else
        echo -e "${GREEN}✅ No recent warning events${NC}"
    fi
    
    echo
}

# Main health check execution
main() {
    check_kubectl
    
    echo -e "${BLUE}📋 Namespace Health Check${NC}"
    echo "========================="
    check_namespace $NAMESPACE_ECOMPULSE
    check_namespace $NAMESPACE_MONITORING
    check_namespace $NAMESPACE_AIRFLOW
    echo
    
    echo -e "${BLUE}🚀 Component Health Checks${NC}"
    echo "=========================="
    check_pods $NAMESPACE_ECOMPULSE "E-ComPulse Platform"
    check_pods $NAMESPACE_MONITORING "Monitoring Stack"
    check_pods $NAMESPACE_AIRFLOW "Airflow"
    
    check_services $NAMESPACE_ECOMPULSE "E-ComPulse Platform"
    check_services $NAMESPACE_MONITORING "Monitoring Stack"
    
    echo -e "${BLUE}🏗️  Infrastructure Health Checks${NC}"
    echo "================================"
    check_nodes
    check_storage
    check_ingress
    
    echo -e "${BLUE}⚙️  Critical Component Status${NC}"
    echo "============================"
    check_critical_deployments
    
    echo -e "${BLUE}🌐 Connectivity Tests${NC}"
    echo "===================="
    check_external_connectivity
    
    echo -e "${BLUE}📊 Resource Monitoring${NC}"
    echo "====================="
    check_resource_usage
    
    echo -e "${BLUE}📰 Recent Events${NC}"
    echo "==============="
    check_recent_events
    
    # Final summary
    echo -e "${BLUE}📋 Health Check Summary${NC}"
    echo "======================"
    
    local total_checks=$((HEALTHY + WARNINGS + CRITICAL))
    
    if [[ $CRITICAL -eq 0 && $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}🎉 All systems healthy! ($total_checks checks passed)${NC}"
        exit 0
    elif [[ $CRITICAL -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  System operational with warnings${NC}"
        echo "   ✅ Healthy: $HEALTHY"
        echo "   ⚠️  Warnings: $WARNINGS"
        echo "   ❌ Critical: $CRITICAL"
        echo
        echo "The platform is operational but review the warnings above."
        exit 0
    else
        echo -e "${RED}🚨 Critical issues detected!${NC}"
        echo "   ✅ Healthy: $HEALTHY"
        echo "   ⚠️  Warnings: $WARNINGS"
        echo "   ❌ Critical: $CRITICAL"
        echo
        echo "Please address the critical issues before the platform can be considered healthy."
        exit 1
    fi
}

# Check for command line arguments
case "${1:-}" in
    --help|-h)
        echo "E-ComPulse Platform Health Check Script"
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --quiet, -q    Reduce output verbosity"
        echo "  --json         Output results in JSON format"
        echo
        echo "This script performs comprehensive health checks on all platform components."
        exit 0
        ;;
    --quiet|-q)
        # Redirect stdout to reduce verbosity
        exec > >(grep -E "(✅|❌|⚠️|🎉|🚨)" || true)
        ;;
    --json)
        echo "JSON output format not implemented yet"
        exit 1
        ;;
esac

# Run main function
main
