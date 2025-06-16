// SBT Assembly plugin for creating fat JARs
addSbtPlugin("com.eed3si9n" % "sbt-assembly" % "2.1.3")

// Coverage plugin for test coverage reporting
addSbtPlugin("org.scoverage" % "sbt-scoverage" % "2.0.9")

// Dependency graph plugin for analyzing dependencies
addSbtPlugin("net.virtual-void" % "sbt-dependency-graph" % "0.10.0-RC1")

// SBT updates plugin to check for dependency updates
addSbtPlugin("com.timushev.sbt" % "sbt-updates" % "0.6.4")

// Scalafmt plugin for code formatting
addSbtPlugin("org.scalameta" % "sbt-scalafmt" % "2.5.2")

// SBT Native Packager for Docker image creation
addSbtPlugin("com.github.sbt" % "sbt-native-packager" % "1.9.16")
