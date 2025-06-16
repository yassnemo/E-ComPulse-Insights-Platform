package com.ecompulse.streaming

import org.apache.spark.sql.{DataFrame, SparkSession}
import org.apache.spark.sql.functions._
import org.apache.spark.sql.streaming.{StreamingQuery, Trigger}
import org.apache.spark.sql.types._
import org.apache.log4j.{Level, Logger}

/**
 * Real-time Session Analytics Job
 * 
 * This Spark Structured Streaming application performs real-time session analysis:
 * - Session window aggregations with configurable timeouts
 * - User behavior tracking and conversion funnel analysis
 * - Cart abandonment detection and alerts
 * - Session-based recommendations and personalization
 * - Real-time customer journey analysis
 * 
 * Features:
 * - Stateful session management with watermarking
 * - Complex event processing for behavior patterns
 * - Real-time alerting for business events
 * - Incremental aggregations for performance
 */
object SessionAnalyticsJob {

  val sessionEventSchema = StructType(Array(
    StructField("event_id", StringType, false),
    StructField("event_type", StringType, false),
    StructField("timestamp", TimestampType, false),
    StructField("user_id", StringType, false),
    StructField("session_id", StringType, false),
    StructField("source", StringType, false),
    StructField("properties", MapType(StringType, StringType), true),
    StructField("metadata", MapType(StringType, StringType), true),
    StructField("customer_segment", StringType, true),
    StructField("event_revenue", DoubleType, true)
  ))

  def main(args: Array[String]): Unit = {
    Logger.getLogger("org").setLevel(Level.WARN)

    val spark = SparkSession.builder()
      .appName("E-ComPulse Session Analytics")
      .config("spark.sql.streaming.checkpointLocation", "s3a://ecompulse-prod-data-lake/checkpoints/session-analytics")
      .config("spark.sql.adaptive.enabled", "true")
      .config("spark.sql.adaptive.coalescePartitions.enabled", "true")
      .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
      .getOrCreate()

    try {
      val queries = startSessionAnalytics(spark)
      queries.foreach(_.awaitTermination())
    } catch {
      case e: Exception =>
        println(s"Error in SessionAnalyticsJob: ${e.getMessage}")
        e.printStackTrace()
        System.exit(1)
    } finally {
      spark.stop()
    }
  }

  def startSessionAnalytics(spark: SparkSession): Array[StreamingQuery] = {
    import spark.implicits._

    // Read enriched events from Kafka
    val enrichedEventsDF = spark
      .readStream
      .format("kafka")
      .option("kafka.bootstrap.servers", sys.env.getOrElse("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"))
      .option("subscribe", "ecommerce-events-enriched")
      .option("startingOffsets", "latest")
      .option("maxOffsetsPerTrigger", "5000")
      .option("kafka.consumer.group.id", "spark-session-analytics")
      .load()

    // Parse enriched events
    val parsedEventsDF = enrichedEventsDF
      .select(from_json(col("value").cast("string"), sessionEventSchema).as("event"))
      .select("event.*")
      .withWatermark("timestamp", "30 minutes")

    // Session aggregations with 30-minute session timeout
    val sessionAggregatesDF = parsedEventsDF
      .groupBy(
        col("session_id"),
        col("user_id"),
        session_window(col("timestamp"), "30 minutes")
      )
      .agg(
        first("timestamp").as("session_start"),
        last("timestamp").as("session_end"),
        count("*").as("total_events"),
        countDistinct("event_type").as("unique_event_types"),
        sum("event_revenue").as("session_revenue"),
        first("customer_segment").as("customer_segment"),
        first("source").as("source"),
        collect_list("event_type").as("event_sequence"),
        collect_list("properties").as("event_properties")
      )
      .withColumn("session_duration_minutes", 
        (unix_timestamp(col("session_end")) - unix_timestamp(col("session_start"))) / 60.0
      )
      .withColumn("has_purchase", array_contains(col("event_sequence"), "purchase"))
      .withColumn("has_cart_activity", 
        array_contains(col("event_sequence"), "add_to_cart") || 
        array_contains(col("event_sequence"), "remove_from_cart")
      )
      .withColumn("abandoned_cart", 
        col("has_cart_activity") && !col("has_purchase")
      )
      .withColumn("conversion_rate", 
        when(col("has_cart_activity"), 
          when(col("has_purchase"), 1.0).otherwise(0.0)
        ).otherwise(null)
      )

    // Real-time conversion funnel analysis
    val conversionFunnelDF = parsedEventsDF
      .withWatermark("timestamp", "10 minutes")
      .groupBy(
        window(col("timestamp"), "5 minutes", "1 minute"),
        col("source"),
        col("customer_segment")
      )
      .agg(
        countDistinct(when(col("event_type") === "page_view", col("session_id"))).as("sessions_with_pageview"),
        countDistinct(when(col("event_type") === "product_view", col("session_id"))).as("sessions_with_product_view"),
        countDistinct(when(col("event_type") === "add_to_cart", col("session_id"))).as("sessions_with_add_to_cart"),
        countDistinct(when(col("event_type") === "purchase", col("session_id"))).as("sessions_with_purchase"),
        sum(when(col("event_type") === "purchase", col("event_revenue"))).as("total_revenue")
      )
      .withColumn("product_view_rate", 
        col("sessions_with_product_view") / col("sessions_with_pageview")
      )
      .withColumn("add_to_cart_rate", 
        col("sessions_with_add_to_cart") / col("sessions_with_product_view")
      )
      .withColumn("conversion_rate", 
        col("sessions_with_purchase") / col("sessions_with_add_to_cart")
      )
      .withColumn("overall_conversion_rate",
        col("sessions_with_purchase") / col("sessions_with_pageview")
      )

    // User behavior patterns analysis
    val userBehaviorDF = parsedEventsDF
      .groupBy(
        col("user_id"),
        window(col("timestamp"), "1 hour", "10 minutes")
      )
      .agg(
        count("*").as("events_count"),
        countDistinct("session_id").as("session_count"),
        countDistinct("event_type").as("unique_event_types"),
        sum("event_revenue").as("hourly_revenue"),
        collect_list("event_type").as("event_sequence"),
        first("customer_segment").as("customer_segment")
      )
      .withColumn("avg_events_per_session", col("events_count") / col("session_count"))
      .withColumn("is_high_activity", col("events_count") > 50)
      .withColumn("behavior_score", calculateBehaviorScore(
        col("events_count"), 
        col("session_count"), 
        col("unique_event_types"),
        col("hourly_revenue")
      ))

    // Real-time alerts for business events
    val alertsDF = sessionAggregatesDF
      .filter(
        col("abandoned_cart") || 
        col("session_revenue") > 500 ||
        col("session_duration_minutes") > 60
      )
      .select(
        col("session_id"),
        col("user_id"),
        col("session_start"),
        col("session_end"),
        col("session_revenue"),
        col("abandoned_cart"),
        when(col("abandoned_cart"), "CART_ABANDONMENT")
          .when(col("session_revenue") > 500, "HIGH_VALUE_SESSION")
          .when(col("session_duration_minutes") > 60, "LONG_SESSION")
          .as("alert_type"),
        current_timestamp().as("alert_timestamp")
      )

    // Write outputs
    val sessionMetricsQuery = writeSessionMetrics(sessionAggregatesDF)
    val conversionFunnelQuery = writeConversionFunnel(conversionFunnelDF)
    val userBehaviorQuery = writeUserBehavior(userBehaviorDF)
    val alertsQuery = writeAlerts(alertsDF)

    Array(sessionMetricsQuery, conversionFunnelQuery, userBehaviorQuery, alertsQuery)
  }

  def calculateBehaviorScore = udf((eventsCount: Int, sessionCount: Int, uniqueEventTypes: Int, revenue: Double) => {
    val activityScore = Math.min(eventsCount / 10.0, 10.0) // Max 10 points for activity
    val diversityScore = Math.min(uniqueEventTypes * 2.0, 10.0) // Max 10 points for diversity
    val revenueScore = Math.min(revenue / 100.0, 10.0) // Max 10 points for revenue
    val sessionScore = Math.min(sessionCount * 5.0, 10.0) // Max 10 points for sessions
    
    (activityScore + diversityScore + revenueScore + sessionScore) / 4.0
  })

  def writeSessionMetrics(df: DataFrame): StreamingQuery = {
    val sessionJson = df
      .select(to_json(struct(df.columns.map(col): _*)).as("value"))

    sessionJson
      .writeStream
      .format("kafka")
      .option("kafka.bootstrap.servers", sys.env.getOrElse("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"))
      .option("topic", "user-sessions")
      .option("checkpointLocation", "s3a://ecompulse-prod-data-lake/checkpoints/session-metrics")
      .outputMode("append")
      .trigger(Trigger.ProcessingTime("30 seconds"))
      .start()
  }

  def writeConversionFunnel(df: DataFrame): StreamingQuery = {
    val funnelJson = df
      .select(
        col("window.start").as("window_start"),
        col("window.end").as("window_end"),
        col("source"),
        col("customer_segment"),
        col("sessions_with_pageview"),
        col("sessions_with_product_view"),
        col("sessions_with_add_to_cart"),
        col("sessions_with_purchase"),
        col("total_revenue"),
        col("product_view_rate"),
        col("add_to_cart_rate"),
        col("conversion_rate"),
        col("overall_conversion_rate"),
        current_timestamp().as("generated_at")
      )
      .select(to_json(struct($"*")).as("value"))

    funnelJson
      .writeStream
      .format("kafka")
      .option("kafka.bootstrap.servers", sys.env.getOrElse("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"))
      .option("topic", "realtime-metrics")
      .option("checkpointLocation", "s3a://ecompulse-prod-data-lake/checkpoints/conversion-funnel")
      .outputMode("append")
      .trigger(Trigger.ProcessingTime("1 minute"))
      .start()
  }

  def writeUserBehavior(df: DataFrame): StreamingQuery = {
    df
      .writeStream
      .format("delta")
      .option("path", "s3a://ecompulse-prod-data-lake/user-behavior")
      .option("checkpointLocation", "s3a://ecompulse-prod-data-lake/checkpoints/user-behavior")
      .partitionBy("customer_segment")
      .outputMode("append")
      .trigger(Trigger.ProcessingTime("2 minutes"))
      .start()
  }

  def writeAlerts(df: DataFrame): StreamingQuery = {
    val alertsJson = df
      .select(to_json(struct(df.columns.map(col): _*)).as("value"))

    alertsJson
      .writeStream
      .format("kafka")
      .option("kafka.bootstrap.servers", sys.env.getOrElse("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"))
      .option("topic", "system-alerts")
      .option("checkpointLocation", "s3a://ecompulse-prod-data-lake/checkpoints/session-alerts")
      .outputMode("append")
      .trigger(Trigger.ProcessingTime("10 seconds"))
      .start()
  }
}
