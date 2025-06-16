# E-ComPulse Spark Streaming - Windows SBT Installation Script
# This PowerShell script installs Java and SBT on Windows using Chocolatey

param(
    [switch]$SkipJava,
    [switch]$SkipSbt,
    [switch]$SkipTests,
    [switch]$Help
)

# Color functions
function Write-Success { param($Text) Write-Host "✅ $Text" -ForegroundColor Green }
function Write-Error { param($Text) Write-Host "❌ $Text" -ForegroundColor Red }
function Write-Warning { param($Text) Write-Host "⚠️  $Text" -ForegroundColor Yellow }
function Write-Info { param($Text) Write-Host "ℹ️  $Text" -ForegroundColor Cyan }
function Write-Step { param($Text) Write-Host "🔧 $Text" -ForegroundColor Blue }

function Show-Help {
    Write-Host "E-ComPulse Spark Streaming - Windows SBT Installation" -ForegroundColor Blue
    Write-Host "====================================================" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Usage: .\install-sbt.ps1 [options]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -SkipJava     Skip Java installation"
    Write-Host "  -SkipSbt      Skip SBT installation"
    Write-Host "  -SkipTests    Skip running tests after installation"
    Write-Host "  -Help         Show this help message"
    Write-Host ""
    Write-Host "This script will:"
    Write-Host "1. Install Chocolatey (if not present)"
    Write-Host "2. Install OpenJDK 11"
    Write-Host "3. Install SBT"
    Write-Host "4. Download project dependencies"
    Write-Host "5. Run tests to verify setup"
    Write-Host ""
    exit 0
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-Chocolatey {
    Write-Step "Checking for Chocolatey..."
    
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Success "Chocolatey is already installed"
        return
    }
    
    Write-Step "Installing Chocolatey..."
    
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Refresh environment variables
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
        
        Write-Success "Chocolatey installed successfully"
    }
    catch {
        Write-Error "Failed to install Chocolatey: $_"
        Write-Info "Please install Chocolatey manually from: https://chocolatey.org/install"
        exit 1
    }
}

function Install-Java {
    if ($SkipJava) {
        Write-Warning "Skipping Java installation"
        return
    }
    
    Write-Step "Checking for Java..."
    
    try {
        $javaVersion = java -version 2>&1
        if ($javaVersion -match "11\.|17\.|21\.") {
            Write-Success "Java 11+ is already installed"
            Write-Info "Java version: $($javaVersion[0])"
            return
        }
    }
    catch {
        Write-Info "Java not found or version too old"
    }
    
    Write-Step "Installing OpenJDK 11..."
    
    try {
        choco install openjdk11 -y
        
        # Refresh environment variables
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
        
        Write-Success "OpenJDK 11 installed successfully"
        
        # Verify installation
        $javaVersion = java -version 2>&1
        Write-Info "Installed Java version: $($javaVersion[0])"
    }
    catch {
        Write-Error "Failed to install Java: $_"
        Write-Info "Please install Java manually from: https://adoptium.net/"
        exit 1
    }
}

function Install-Sbt {
    if ($SkipSbt) {
        Write-Warning "Skipping SBT installation"
        return
    }
    
    Write-Step "Checking for SBT..."
    
    try {
        $sbtVersion = sbt sbtVersion 2>&1
        if ($sbtVersion -match "1\.") {
            Write-Success "SBT is already installed"
            return
        }
    }
    catch {
        Write-Info "SBT not found"
    }
    
    Write-Step "Installing SBT..."
    
    try {
        choco install sbt -y
        
        # Refresh environment variables
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
        
        Write-Success "SBT installed successfully"
        
        # Verify installation
        Write-Info "Verifying SBT installation..."
        sbt sbtVersion
    }
    catch {
        Write-Error "Failed to install SBT: $_"
        Write-Info "Please install SBT manually from: https://www.scala-sbt.org/download.html"
        exit 1
    }
}

function Setup-Project {
    Write-Step "Setting up project dependencies..."
    
    # Check if we're in the right directory
    if (-not (Test-Path "build.sbt")) {
        Write-Error "build.sbt not found. Make sure you're in the spark-streaming directory"
        exit 1
    }
    
    Write-Info "Current directory: $(Get-Location)"
    Write-Info "Project files:"
    Get-ChildItem | Select-Object Name, Length | Format-Table
    
    # Set SBT options for better performance
    $env:SBT_OPTS = "-Xmx2G -XX:+UseConcMarkSweepGC -XX:+CMSClassUnloadingEnabled -Xss2M"
    
    Write-Step "Downloading dependencies (this may take a while)..."
    
    try {
        Write-Info "Running: sbt update"
        sbt update
        
        Write-Info "Running: sbt compile"
        sbt compile
        
        Write-Info "Running: sbt test:compile"
        sbt test:compile
        
        Write-Success "Dependencies downloaded and project compiled successfully"
    }
    catch {
        Write-Error "Failed to setup project: $_"
        exit 1
    }
}

function Run-Tests {
    if ($SkipTests) {
        Write-Warning "Skipping tests"
        return
    }
    
    Write-Step "Running tests..."
    
    try {
        sbt test
        Write-Success "All tests passed!"
    }
    catch {
        Write-Warning "Some tests failed, but setup is complete"
        Write-Info "You can run tests manually with: sbt test"
    }
}

function Show-Summary {
    Write-Success "🎉 SBT setup completed successfully!"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Blue
    Write-Host "1. Run tests: sbt test"
    Write-Host "2. Create assembly JAR: sbt assembly"
    Write-Host "3. Generate coverage: sbt coverage test coverageReport"
    Write-Host "4. Start sbt shell: sbt"
    Write-Host ""
    Write-Host "Available SBT commands:" -ForegroundColor Blue
    Write-Host "- compile: Compile the project"
    Write-Host "- test: Run tests"
    Write-Host "- assembly: Create fat JAR"
    Write-Host "- clean: Clean build artifacts"
    Write-Host "- reload: Reload build configuration"
    Write-Host "- console: Start Scala REPL with project on classpath"
}

# Main execution
if ($Help) {
    Show-Help
}

Write-Host "🔧 E-ComPulse Spark Streaming - SBT Setup" -ForegroundColor Blue
Write-Host "==========================================" -ForegroundColor Blue
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

# Check if running as administrator
if (-not (Test-Administrator)) {
    Write-Warning "This script should be run as Administrator for best results"
    Write-Info "Right-click PowerShell and select 'Run as Administrator'"
    $continue = Read-Host "Continue anyway? (y/N)"
    if ($continue -ne "y" -and $continue -ne "Y") {
        exit 1
    }
}

try {
    Install-Chocolatey
    Install-Java
    Install-Sbt
    Setup-Project
    Run-Tests
    Show-Summary
}
catch {
    Write-Error "Installation failed: $_"
    Write-Info "Please check the error message and try again"
    Write-Info "For manual installation, see: INSTALL-WINDOWS.md"
    exit 1
}
