package com.ecompulse.streaming

import org.apache.spark.sql.{DataFrame, SparkSession}
import org.apache.spark.sql.functions._
import org.apache.spark.sql.streaming.{StreamingQuery, Trigger}
import org.apache.spark.sql.types._
import org.apache.log4j.{Level, Logger}
import scala.util.Random

/**
 * Demo E-commerce Event Stream Generator and Processor
 * 
 * This demonstrates the Spark Streaming capabilities by:
 * - Generating synthetic e-commerce events in real-time
 * - Processing and enriching events with business logic
 * - Displaying results in the console for demonstration
 */
object DemoStreamingJob {

  def main(args: Array[String]): Unit = {
    // Set log level to reduce noise
    Logger.getLogger("org").setLevel(Level.WARN)
    Logger.getLogger("akka").setLevel(Level.WARN)

    // Create Spark session
    val spark = SparkSession.builder()
      .appName("EComPulse-Demo-Streaming")
      .master("local[*]")
      .config("spark.sql.adaptive.enabled", "true")
      .config("spark.sql.adaptive.coalescePartitions.enabled", "true")
      .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
      .config("spark.sql.streaming.checkpointLocation", "target/checkpoint")
      .getOrCreate()

    println("🚀 Starting E-ComPulse Demo Streaming Job...")
    println("=" * 60)
    
    try {
      val queries = startDemoStreaming(spark)
      
      println("📊 Real-time analytics are now running!")
      println("Press Ctrl+C to stop the demo...")
      println("=" * 60)
      
      queries.foreach(_.awaitTermination())
      
    } catch {
      case e: Exception =>
        println(s"❌ Error in Demo: ${e.getMessage}")
        e.printStackTrace()
    } finally {
      spark.stop()
    }
  }

  def startDemoStreaming(spark: SparkSession): Array[StreamingQuery] = {
    import spark.implicits._

    // Generate synthetic e-commerce events
    val syntheticEvents = spark
      .readStream
      .format("rate")
      .option("rowsPerSecond", "10") // Generate 10 events per second
      .option("rampUpTime", "5s")
      .load()      .select(
        col("timestamp"),
        (rand() * 1000).cast("long").as("user_id"),
        when(rand() < 0.3, "page_view")
          .when(rand() < 0.5, "product_view")
          .when(rand() < 0.7, "add_to_cart")
          .when(rand() < 0.85, "search")
          .when(rand() < 0.95, "remove_from_cart")
          .otherwise("purchase").as("event_type"),
        (rand() * 10000).cast("long").as("product_id"),
        when(rand() < 0.1, rand() * 500 + 10).otherwise(null).as("price"),
        when(rand() < 0.5, "web")
          .when(rand() < 0.8, "mobile")
          .otherwise("tablet").as("source"),
        when(rand() < 0.4, "US")
          .when(rand() < 0.6, "UK")
          .when(rand() < 0.75, "CA")
          .when(rand() < 0.9, "DE")
          .otherwise("FR").as("country")
      )

    // Enrich events with business logic
    val enrichedEvents = syntheticEvents
      .withColumn("session_id", concat(col("user_id"), lit("_"), 
        date_format(col("timestamp"), "yyyyMMddHH")))
      .withColumn("is_mobile", col("source") === "mobile")
      .withColumn("event_value", 
        when(col("event_type") === "page_view", 1)
        .when(col("event_type") === "product_view", 3)
        .when(col("event_type") === "add_to_cart", 10)
        .when(col("event_type") === "purchase", 100)
        .otherwise(0))
      .withColumn("customer_segment",
        when(col("price") > 200, "premium")
        .when(col("price") > 50, "standard")
        .otherwise("budget"))

    // Real-time event metrics
    val eventMetrics = enrichedEvents
      .withWatermark("timestamp", "30 seconds")
      .groupBy(
        window(col("timestamp"), "30 seconds", "10 seconds"),
        col("event_type"),
        col("source")
      )
      .agg(
        count("*").as("event_count"),
        sum("event_value").as("total_value"),
        countDistinct("user_id").as("unique_users"),
        avg("price").as("avg_price")
      )
      .select(
        col("window.start").as("window_start"),
        col("window.end").as("window_end"),
        col("event_type"),
        col("source"),
        col("event_count"),
        col("total_value"),
        col("unique_users"),
        round(col("avg_price"), 2).as("avg_price")
      )

    // User behavior analysis
    val userBehavior = enrichedEvents
      .withWatermark("timestamp", "1 minute")
      .groupBy(
        window(col("timestamp"), "1 minute"),
        col("user_id")
      )
      .agg(
        count("*").as("events_per_minute"),
        collect_set("event_type").as("event_types"),
        sum("event_value").as("user_score"),
        max("price").as("max_purchase"),
        first("country").as("country")
      )
      .select(
        col("window.start").as("window_start"),
        col("user_id"),
        col("events_per_minute"),
        size(col("event_types")).as("unique_event_types"),
        col("user_score"),
        col("max_purchase"),
        col("country")
      )
      .filter(col("events_per_minute") > 2) // Only active users

    // Output raw events to console
    val rawEventsQuery = enrichedEvents
      .writeStream
      .outputMode("append")
      .format("console")
      .option("truncate", false)
      .option("numRows", 5)
      .trigger(Trigger.ProcessingTime("10 seconds"))
      .start()

    // Output metrics to console
    val metricsQuery = eventMetrics
      .writeStream
      .outputMode("complete")
      .format("console")
      .option("truncate", false)
      .trigger(Trigger.ProcessingTime("30 seconds"))
      .start()

    // Output user behavior to console
    val behaviorQuery = userBehavior
      .writeStream
      .outputMode("append")
      .format("console")
      .option("truncate", false)
      .option("numRows", 10)
      .trigger(Trigger.ProcessingTime("1 minute"))
      .start()

    Array(rawEventsQuery, metricsQuery, behaviorQuery)
  }
}
