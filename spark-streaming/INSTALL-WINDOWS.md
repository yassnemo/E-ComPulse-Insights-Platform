# SBT Installation Guide for Windows

## Prerequisites

### 1. Install Java 11 or Higher

**Option A: Using Chocolatey (Recommended)**
```powershell
# Install Chocolatey if not already installed
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install OpenJDK 11
choco install openjdk11
```

**Option B: Manual Installation**
1. Download OpenJDK 11 from: https://adoptium.net/
2. Run the installer
3. Add `JAVA_HOME` environment variable pointing to the JDK installation directory
4. Add `%JAVA_HOME%\bin` to your PATH

### 2. Install SBT

**Option A: Using Chocolatey**
```powershell
choco install sbt
```

**Option B: Manual Installation**
1. Download SBT from: https://www.scala-sbt.org/download.html
2. Choose "Windows (msi)" installer
3. Run the installer
4. SBT will be automatically added to PATH

**Option C: Using SDKMAN (if available)**
```bash
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install java 11.0.20-tem
sdk install sbt
```

## Verification

After installation, open a new terminal and verify:

```bash
# Check Java
java -version
# Should show: openjdk version "11.x.x"

# Check SBT
sbt sbtVersion
# Should show: [info] 1.9.6
```

## Project Setup

Once SBT is installed, navigate to the spark-streaming directory and run:

```bash
cd f:/Project/E-ComPulse-insights-platform/spark-streaming

# Download dependencies
sbt update

# Compile project
sbt compile

# Compile tests
sbt test:compile

# Run tests
sbt test

# Create assembly JAR
sbt assembly
```

## Common Issues and Solutions

### Issue 1: "java: command not found"
**Solution:** 
- Restart your terminal after Java installation
- Verify JAVA_HOME is set: `echo $JAVA_HOME`
- Verify PATH includes Java: `echo $PATH | grep -i java`

### Issue 2: "sbt: command not found"
**Solution:**
- Restart your terminal after SBT installation
- On Windows, make sure SBT is in your PATH
- Try using the full path: `C:\Program Files (x86)\sbt\bin\sbt.bat`

### Issue 3: Permission denied
**Solution:**
- Run terminal as Administrator
- Check file permissions: `ls -la`

### Issue 4: Network/Proxy Issues
**Solution:**
```bash
# Configure SBT for proxy (if needed)
export SBT_OPTS="-Dhttp.proxyHost=yourproxy -Dhttp.proxyPort=8080 -Dhttps.proxyHost=yourproxy -Dhttps.proxyPort=8080"
```

### Issue 5: Out of Memory
**Solution:**
```bash
# Increase SBT memory
export SBT_OPTS="-Xmx2G -XX:+UseConcMarkSweepGC -XX:+CMSClassUnloadingEnabled -Xss2M"
```

## Alternative: Using Docker

If you prefer to use Docker instead of installing Java/SBT locally:

```bash
# Build with Docker
docker run --rm -v "$(pwd)":/workspace -w /workspace sbtscala/scala-sbt:openjdk-11u2_1.9.6_2.12.15 sbt compile test

# Interactive SBT session
docker run -it --rm -v "$(pwd)":/workspace -w /workspace sbtscala/scala-sbt:openjdk-11u2_1.9.6_2.12.15 sbt
```

## Next Steps

After successful installation:

1. **Run Tests**: `sbt test`
2. **Generate Coverage**: `sbt coverage test coverageReport`
3. **Create Assembly**: `sbt assembly`
4. **Start SBT Shell**: `sbt` (interactive mode)
5. **Clean Build**: `sbt clean compile`

## SBT Commands Reference

| Command | Description |
|---------|-------------|
| `sbt compile` | Compile main sources |
| `sbt test:compile` | Compile test sources |
| `sbt test` | Run all tests |
| `sbt "testOnly ClassName"` | Run specific test |
| `sbt assembly` | Create fat JAR |
| `sbt clean` | Clean build artifacts |
| `sbt reload` | Reload build configuration |
| `sbt console` | Start Scala REPL |
| `sbt dependencyTree` | Show dependency tree |
| `sbt update` | Download dependencies |

## IDE Integration

### IntelliJ IDEA
1. Install Scala plugin
2. Import project as SBT project
3. Let IntelliJ download dependencies

### VS Code
1. Install "Metals" extension
2. Open spark-streaming folder
3. Run "Metals: Import build" command
