package com.ecompulse.streaming

import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._

object QuickDemo {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("EComPulse-Quick-Demo")
      .master("local[2]")
      .getOrCreate()

    println("🚀 E-ComPulse Platform - Quick Demo")
    println("==================================")
    
    import spark.implicits._

    // Create sample data
    val data = Seq(
      ("user1", "purchase", 150.0, "2025-06-16 20:45:00"),
      ("user2", "page_view", 0.0, "2025-06-16 20:45:01"),
      ("user1", "add_to_cart", 75.0, "2025-06-16 20:45:02"),
      ("user3", "purchase", 299.99, "2025-06-16 20:45:03"),
      ("user2", "product_view", 0.0, "2025-06-16 20:45:04")
    ).toDF("user_id", "event_type", "value", "timestamp")

    println("📊 Sample E-commerce Events:")
    data.show(false)

    println("💰 Revenue by Event Type:")
    data.groupBy("event_type")
      .agg(
        count("*").as("event_count"),
        sum("value").as("total_revenue"),
        countDistinct("user_id").as("unique_users")
      )
      .orderBy(desc("total_revenue"))
      .show(false)

    println("👤 User Activity Summary:")
    data.groupBy("user_id")
      .agg(
        count("*").as("events"),
        sum("value").as("total_spent"),
        collect_set("event_type").as("event_types")
      )
      .orderBy(desc("total_spent"))
      .show(false)

    println("✅ Demo completed! This shows the data processing capabilities.")
    println("🌐 For real-time streaming, the full demo would show live updates.")
    
    spark.stop()
  }
}
