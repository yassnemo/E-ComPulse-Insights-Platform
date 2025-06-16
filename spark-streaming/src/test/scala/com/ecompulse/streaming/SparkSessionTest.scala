package com.ecompulse.streaming

import org.apache.spark.sql.{DataFrame, SparkSession}
import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import org.scalatest.BeforeAndAfterAll

class SparkSessionTest extends AnyFunSuite with Matchers with BeforeAndAfterAll {

  var spark: SparkSession = _

  override def beforeAll(): Unit = {
    spark = SparkSession.builder()
      .appName("EComPulse-Streaming-Test")
      .master("local[2]")
      .config("spark.sql.adaptive.enabled", "true")
      .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
      .getOrCreate()
    
    spark.sparkContext.setLogLevel("WARN")
  }

  override def afterAll(): Unit = {
    if (spark != null) {
      spark.stop()
    }
  }

  test("Spark session should be created successfully") {
    spark should not be null
    spark.version should not be empty
  }

  test("Basic DataFrame operations") {
    import spark.implicits._
    
    val data = Seq(
      ("user1", "page_view", "2023-01-01", 1),
      ("user2", "purchase", "2023-01-01", 5),
      ("user1", "add_to_cart", "2023-01-01", 2)
    )
    
    val df = data.toDF("user_id", "event_type", "date", "count")
    
    df.count() shouldEqual 3
    df.columns should contain allOf("user_id", "event_type", "date", "count")
    
    val userEvents = df.filter($"user_id" === "user1")
    userEvents.count() shouldEqual 2
  }

  test("Event aggregation logic") {
    import spark.implicits._
    
    val events = Seq(
      ("user1", "page_view", 100L),
      ("user1", "page_view", 200L),
      ("user2", "purchase", 150L),
      ("user1", "purchase", 300L)
    ).toDF("user_id", "event_type", "timestamp")
    
    val aggregated = events
      .groupBy($"user_id", $"event_type")
      .count()
      .orderBy($"user_id", $"event_type")
    
    val results = aggregated.collect()
    results should have length 3
    
    // Check specific aggregation results
    val user1PageViews = results.find(row => 
      row.getString(0) == "user1" && row.getString(1) == "page_view"
    )
    user1PageViews.get.getLong(2) shouldEqual 2
  }

  test("JSON parsing simulation") {
    import spark.implicits._
    
    val jsonData = Seq(
      """{"user_id": "user1", "event_type": "page_view", "timestamp": 1234567890}""",
      """{"user_id": "user2", "event_type": "purchase", "timestamp": 1234567891}"""
    )
    
    val df = jsonData.toDF("json_string")
    df.count() shouldEqual 2
    
    // Simulate JSON parsing validation
    val validJsonCount = df.filter($"json_string".contains("user_id")).count()
    validJsonCount shouldEqual 2
  }
}
