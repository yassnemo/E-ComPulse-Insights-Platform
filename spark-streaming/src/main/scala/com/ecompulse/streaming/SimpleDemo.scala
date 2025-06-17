package com.ecompulse.streaming

import org.apache.spark.sql.{SparkSession}
import org.apache.spark.sql.functions._
import org.apache.spark.sql.streaming.Trigger
import org.apache.log4j.{Level, Logger}

/**
 * Simple Spark Streaming Demo
 * Shows real-time processing capabilities with basic rate source
 */
object SimpleDemo {

  def main(args: Array[String]): Unit = {
    Logger.getLogger("org").setLevel(Level.WARN)
    Logger.getLogger("akka").setLevel(Level.WARN)

    val spark = SparkSession.builder()
      .appName("EComPulse-Simple-Demo")
      .master("local[*]")
      .config("spark.sql.streaming.checkpointLocation", "target/simple-checkpoint")
      .getOrCreate()

    println("🚀 E-ComPulse Streaming Platform Demo")
    println("=====================================")
    println("📊 Processing simulated e-commerce events...")
    println("🌐 Spark UI available at: http://localhost:4040")
    println("⏹️  Press Ctrl+C to stop")
    println("=====================================")

    try {
      import spark.implicits._

      // Generate synthetic events
      val events = spark
        .readStream
        .format("rate")
        .option("rowsPerSecond", "5")
        .load()
        .select(
          col("timestamp"),
          (col("value") % 100).as("user_id"),
          when(col("value") % 4 === 0, "purchase")
            .when(col("value") % 4 === 1, "page_view")
            .when(col("value") % 4 === 2, "add_to_cart")
            .otherwise("product_view").as("event_type"),
          (rand() * 100 + 10).as("value_usd")
        )

      // Real-time aggregations
      val summary = events
        .withWatermark("timestamp", "10 seconds")
        .groupBy(
          window(col("timestamp"), "20 seconds", "5 seconds"),
          col("event_type")
        )
        .agg(
          count("*").as("count"),
          sum("value_usd").as("total_value"),
          countDistinct("user_id").as("unique_users")
        )

      // Output to console
      val query = summary
        .writeStream
        .outputMode("update")
        .format("console")
        .option("truncate", false)
        .trigger(Trigger.ProcessingTime("10 seconds"))
        .start()

      query.awaitTermination()

    } catch {
      case e: Exception =>
        println(s"❌ Error: ${e.getMessage}")
        e.printStackTrace()
    } finally {
      spark.stop()
    }
  }
}
