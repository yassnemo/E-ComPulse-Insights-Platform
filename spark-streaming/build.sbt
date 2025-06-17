// Enable plugins
enablePlugins(JavaAppPackaging, DockerPlugin)

name := "ecompulse-streaming"
version := "1.0.0"
scalaVersion := "2.12.15"

// Coverage settings
coverageEnabled := true
coverageMinimumStmtTotal := 80
coverageFailOnMinimum := false
coverageHighlighting := true
coverageExcludedPackages := ".*Main.*;.*App.*"

val sparkVersion = "3.4.1"
val deltaVersion = "2.4.0"
val kafkaVersion = "3.5.0"

libraryDependencies ++= Seq(
  // Spark Core - use "compile" for local development, "provided" for cluster
  "org.apache.spark" %% "spark-core" % sparkVersion % "compile",
  "org.apache.spark" %% "spark-sql" % sparkVersion % "compile", 
  "org.apache.spark" %% "spark-streaming" % sparkVersion % "compile",
  
  // Spark Structured Streaming
  "org.apache.spark" %% "spark-sql-kafka-0-10" % sparkVersion,
  "org.apache.spark" %% "spark-streaming-kafka-0-10" % sparkVersion,
  
  // Delta Lake for ACID transactions
  "io.delta" %% "delta-core" % deltaVersion,
  
  // AWS SDK for S3 integration
  "com.amazonaws" % "aws-java-sdk-bundle" % "1.12.565",
  "org.apache.hadoop" % "hadoop-aws" % "3.3.4",
  
  // Redis client for caching
  "redis.clients" % "jedis" % "4.4.3",
  
  // DynamoDB for metadata lookups
  "software.amazon.awssdk" % "dynamodb" % "2.20.162",
  
  // JSON processing
  "com.fasterxml.jackson.core" % "jackson-core" % "2.15.2",
  "com.fasterxml.jackson.core" % "jackson-databind" % "2.15.2",
  "com.fasterxml.jackson.module" %% "jackson-module-scala" % "2.15.2",
  
  // Configuration management
  "com.typesafe" % "config" % "1.4.2",
  
  // Logging
  "org.slf4j" % "slf4j-api" % "1.7.36",
  "ch.qos.logback" % "logback-classic" % "1.2.12",
  
  // Metrics and monitoring
  "io.prometheus" % "simpleclient" % "0.16.0",
  "io.prometheus" % "simpleclient_hotspot" % "0.16.0",
  "io.prometheus" % "simpleclient_servlet" % "0.16.0",
  
  // Testing
  "org.scalatest" %% "scalatest" % "3.2.17" % Test,
  "org.apache.spark" %% "spark-sql" % sparkVersion % Test classifier "tests",
  "org.apache.spark" %% "spark-core" % sparkVersion % Test classifier "tests",
  "org.testcontainers" % "testcontainers" % "1.19.1" % Test,
  "org.testcontainers" % "kafka" % "1.19.1" % Test
)

// Assembly settings for fat JAR creation
assembly / assemblyMergeStrategy := {
  case PathList("META-INF", xs @ _*) => MergeStrategy.discard
  case PathList("reference.conf") => MergeStrategy.concat
  case PathList("application.conf") => MergeStrategy.concat
  case "log4j.properties" => MergeStrategy.first
  case x if x.endsWith(".class") => MergeStrategy.first
  case x if x.endsWith(".properties") => MergeStrategy.first
  case x if x.endsWith(".xml") => MergeStrategy.first
  case _ => MergeStrategy.first
}

assembly / assemblyExcludedJars := {
  val cp = (assembly / fullClasspath).value
  cp filter { jar =>
    jar.data.getName.startsWith("spark-core") ||
    jar.data.getName.startsWith("spark-sql") ||
    jar.data.getName.startsWith("spark-streaming") ||
    jar.data.getName.startsWith("hadoop-client") ||
    jar.data.getName.startsWith("scala-library")
  }
}

// Compiler options
scalacOptions ++= Seq(
  "-target:jvm-1.8",
  "-encoding", "UTF-8",
  "-unchecked",
  "-deprecation",
  "-feature",
  "-Xlint",
  "-Ywarn-dead-code",
  "-Ywarn-numeric-widen",
  "-Ywarn-value-discard"
)

// Java compiler options
javacOptions ++= Seq(
  "-source", "1.8",
  "-target", "1.8",
  "-encoding", "UTF-8",
  "-Xlint:unchecked",
  "-Xlint:deprecation"
)

// Test settings
Test / parallelExecution := false
Test / fork := true
Test / javaOptions ++= Seq(
  "-Xmx2g",
  "-XX:+CMSClassUnloadingEnabled"
)

// Runtime settings
run / javaOptions ++= Seq(
  "-Xmx4g",
  "-XX:+UseG1GC",
  "-XX:+UseStringDeduplication",
  "-Djava.security.egd=file:/dev/./urandom"
)

// Assembly artifact name
assembly / assemblyJarName := s"${name.value}-${version.value}-assembly.jar"
