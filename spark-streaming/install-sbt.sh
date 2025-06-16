#!/bin/bash

# E-ComPulse Spark Streaming - SBT Installation Script
# This script installs SBT and downloads all project dependencies

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 E-ComPulse Spark Streaming - SBT Setup${NC}"
echo "==========================================="
echo "Timestamp: $(date)"
echo

# Function to detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

# Function to check if command exists
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✅ $1 is installed${NC}"
        return 0
    else
        echo -e "${RED}❌ $1 is not installed${NC}"
        return 1
    fi
}

# Function to install SBT on different platforms
install_sbt() {
    local os=$(detect_os)
    echo -e "${BLUE}📦 Installing SBT for $os...${NC}"
    
    case $os in
        "linux")
            echo "Installing SBT on Linux..."
            # Add SBT repository
            echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | sudo tee /etc/apt/sources.list.d/sbt.list
            echo "deb https://repo.scala-sbt.org/scalasbt/debian /" | sudo tee /etc/apt/sources.list.d/sbt_old.list
            
            # Add GPG key
            curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x2EE0EA64E40A89B84B2DF73499E82A75642AC823" | sudo apt-key add
            
            # Update and install
            sudo apt-get update
            sudo apt-get install -y sbt
            ;;
        "macos")
            echo "Installing SBT on macOS..."
            if command -v brew &> /dev/null; then
                brew install sbt
            else
                echo -e "${RED}❌ Homebrew not found. Please install Homebrew first.${NC}"
                echo "Visit: https://brew.sh/"
                exit 1
            fi
            ;;
        "windows")
            echo "For Windows, please install SBT manually:"
            echo "1. Download from: https://www.scala-sbt.org/download.html"
            echo "2. Run the installer"
            echo "3. Add SBT to your PATH"
            echo "4. Restart your terminal"
            exit 1
            ;;
        *)
            echo -e "${RED}❌ Unsupported OS: $os${NC}"
            echo "Please install SBT manually from: https://www.scala-sbt.org/download.html"
            exit 1
            ;;
    esac
}

# Function to check Java installation
check_java() {
    echo -e "${BLUE}☕ Checking Java installation...${NC}"
    
    if check_command "java"; then
        local java_version=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2)
        echo "Java version: $java_version"
        
        # Check if Java 11 is available
        if java -version 2>&1 | grep -q "11\."; then
            echo -e "${GREEN}✅ Java 11 detected${NC}"
        else
            echo -e "${YELLOW}⚠️  Java 11 recommended for Spark 3.4.1${NC}"
        fi
    else
        echo -e "${RED}❌ Java not found${NC}"
        echo "Please install Java 11 or higher:"
        echo "- Ubuntu: sudo apt-get install openjdk-11-jdk"
        echo "- macOS: brew install openjdk@11"
        echo "- Windows: Download from Oracle or OpenJDK"
        exit 1
    fi
}

# Function to verify SBT installation
verify_sbt() {
    echo -e "${BLUE}🔍 Verifying SBT installation...${NC}"
    
    if check_command "sbt"; then
        echo "SBT version:"
        sbt sbtVersion
        echo -e "${GREEN}✅ SBT installation verified${NC}"
    else
        echo -e "${RED}❌ SBT installation failed${NC}"
        exit 1
    fi
}

# Function to download dependencies
download_dependencies() {
    echo -e "${BLUE}📥 Downloading project dependencies...${NC}"
    
    # Change to spark-streaming directory
    cd "$(dirname "$0")/.."
    
    echo "Current directory: $(pwd)"
    echo "Project structure:"
    ls -la
    
    if [[ ! -f "build.sbt" ]]; then
        echo -e "${RED}❌ build.sbt not found${NC}"
        echo "Make sure you're running this script from the spark-streaming directory"
        exit 1
    fi
    
    echo -e "${BLUE}📋 Project configuration:${NC}"
    echo "build.sbt contents:"
    head -10 build.sbt
    
    echo -e "${BLUE}🔄 Downloading dependencies (this may take a while)...${NC}"
    
    # Set SBT options for better performance
    export SBT_OPTS="-Xmx2G -XX:+UseConcMarkSweepGC -XX:+CMSClassUnloadingEnabled -Xss2M"
    
    # Download dependencies
    echo "Running: sbt update"
    sbt update
    
    echo "Running: sbt compile"
    sbt compile
    
    echo "Running: sbt test:compile"
    sbt test:compile
    
    echo -e "${GREEN}✅ Dependencies downloaded and project compiled${NC}"
}

# Function to run tests
run_tests() {
    echo -e "${BLUE}🧪 Running tests...${NC}"
    
    echo "Running: sbt test"
    sbt test
    
    echo -e "${GREEN}✅ Tests completed${NC}"
}

# Function to show dependency tree
show_dependencies() {
    echo -e "${BLUE}📊 Dependency tree:${NC}"
    sbt dependencyTree | head -30
    echo "..."
    echo "(Use 'sbt dependencyTree' to see full tree)"
}

# Main installation process
main() {
    echo "Starting SBT installation and setup process..."
    echo
    
    # Check prerequisites
    check_java
    echo
    
    # Install SBT if not present
    if ! check_command "sbt"; then
        install_sbt
        echo
    else
        echo -e "${GREEN}✅ SBT already installed${NC}"
    fi
    
    # Verify SBT installation
    verify_sbt
    echo
    
    # Download dependencies
    download_dependencies
    echo
    
    # Show dependency information
    show_dependencies
    echo
    
    # Run tests to verify everything works
    if [[ "${1:-}" != "--skip-tests" ]]; then
        run_tests
        echo
    fi
    
    echo -e "${GREEN}🎉 SBT setup completed successfully!${NC}"
    echo
    echo "Next steps:"
    echo "1. Run tests: sbt test"
    echo "2. Create assembly JAR: sbt assembly"
    echo "3. Generate coverage: sbt coverage test coverageReport"
    echo "4. Start sbt shell: sbt"
    echo
    echo "Available SBT commands:"
    echo "- compile: Compile the project"
    echo "- test: Run tests"
    echo "- assembly: Create fat JAR"
    echo "- clean: Clean build artifacts"
    echo "- reload: Reload build configuration"
    echo "- console: Start Scala REPL with project on classpath"
}

# Check for help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "E-ComPulse Spark Streaming - SBT Installation Script"
    echo "==================================================="
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --help, -h        Show this help message"
    echo "  --skip-tests      Skip running tests after installation"
    echo
    echo "This script will:"
    echo "1. Check Java installation"
    echo "2. Install SBT (if not present)"
    echo "3. Download all project dependencies"
    echo "4. Compile the project"
    echo "5. Run tests to verify setup"
    echo
    exit 0
fi

# Run main function
main "$@"
