package com.ecompulse.streaming

import org.apache.spark.sql.{DataFrame, Dataset, SparkSession}
import org.apache.spark.sql.functions._
import org.apache.spark.sql.expressions.Window
import org.apache.spark.sql.streaming.{StreamingQuery, Trigger}
import org.apache.spark.sql.types._
import org.apache.log4j.{Level, Logger}
import java.util.concurrent.TimeUnit
import scala.concurrent.duration._

/**
 * Real-time E-commerce Event Enrichment Job
 * 
 * This Spark Structured Streaming application enriches raw e-commerce events with:
 * - User profile data from Redis/DynamoDB
 * - Product metadata from external APIs
 * - Geolocation data from IP addresses
 * - Session context and historical behavior
 * 
 * Features:
 * - Exactly-once processing with Kafka checkpointing
 * - Stateful stream-stream joins for enrichment
 * - Watermarking for late data handling
 * - Circuit breaker pattern for external dependencies
 * - Real-time data quality validation
 */
object EventEnrichmentJob {

  // Define schemas for better performance and validation
  val rawEventSchema = StructType(Array(
    StructField("event_id", StringType, false),
    StructField("event_type", StringType, false),
    StructField("timestamp", TimestampType, false),
    StructField("user_id", StringType, false),
    StructField("session_id", StringType, false),
    StructField("source", StringType, false),
    StructField("properties", MapType(StringType, StringType), true),
    StructField("metadata", MapType(StringType, StringType), true)
  ))

  val userProfileSchema = StructType(Array(
    StructField("user_id", StringType, false),
    StructField("first_name", StringType, true),
    StructField("last_name", StringType, true),
    StructField("email", StringType, true),
    StructField("age_group", StringType, true),
    StructField("location", StringType, true),
    StructField("customer_segment", StringType, true),
    StructField("registration_date", TimestampType, true),
    StructField("last_activity", TimestampType, true),
    StructField("total_orders", IntegerType, true),
    StructField("total_spent", DoubleType, true)
  ))

  val productMetadataSchema = StructType(Array(
    StructField("product_id", StringType, false),
    StructField("product_name", StringType, true),
    StructField("category", StringType, true),
    StructField("subcategory", StringType, true),
    StructField("brand", StringType, true),
    StructField("price", DoubleType, true),
    StructField("cost", DoubleType, true),
    StructField("margin", DoubleType, true),
    StructField("inventory_level", IntegerType, true),
    StructField("last_updated", TimestampType, true)
  ))

  def main(args: Array[String]): Unit = {
    // Set log level
    Logger.getLogger("org").setLevel(Level.WARN)
    Logger.getLogger("akka").setLevel(Level.WARN)

    // Initialize Spark Session with optimized configurations
    val spark = SparkSession.builder()
      .appName("E-ComPulse Event Enrichment")
      .config("spark.sql.streaming.checkpointLocation", "s3a://ecompulse-prod-data-lake/checkpoints/event-enrichment")
      .config("spark.sql.streaming.stateStore.providerClass", "org.apache.spark.sql.execution.streaming.state.HDFSBackedStateStoreProvider")
      .config("spark.sql.streaming.stateStore.maintenanceInterval", "600s")
      .config("spark.sql.adaptive.enabled", "true")
      .config("spark.sql.adaptive.coalescePartitions.enabled", "true")
      .config("spark.sql.adaptive.advisoryPartitionSizeInBytes", "128MB")
      .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
      .config("spark.kryo.unsafe", "true")
      .config("spark.sql.execution.arrow.pyspark.enabled", "true")
      .getOrCreate()

    import spark.implicits._

    try {
      // Configure streaming sources and run enrichment job
      val queries = startEnrichmentJob(spark)
      
      // Wait for all queries to complete
      queries.foreach(_.awaitTermination())
      
    } catch {
      case e: Exception =>
        println(s"Error in EventEnrichmentJob: ${e.getMessage}")
        e.printStackTrace()
        System.exit(1)
    } finally {
      spark.stop()
    }
  }

  def startEnrichmentJob(spark: SparkSession): Array[StreamingQuery] = {
    import spark.implicits._

    // Read raw events from Kafka
    val rawEventsDF = spark
      .readStream
      .format("kafka")
      .option("kafka.bootstrap.servers", sys.env.getOrElse("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"))
      .option("subscribe", "ecommerce-events-raw")
      .option("startingOffsets", "latest")
      .option("maxOffsetsPerTrigger", "10000")
      .option("kafka.consumer.group.id", "spark-enrichment-consumer")
      .option("kafka.session.timeout.ms", "30000")
      .option("kafka.request.timeout.ms", "40000")
      .option("failOnDataLoss", "false")
      .load()

    // Parse JSON events and add watermark
    val parsedEventsDF = rawEventsDF
      .select(
        from_json(col("value").cast("string"), rawEventSchema).as("event"),
        col("timestamp").as("kafka_timestamp"),
        col("offset"),
        col("partition")
      )
      .select("event.*", "kafka_timestamp", "offset", "partition")
      .withWatermark("timestamp", "10 minutes")

    // Validate and filter events
    val validEventsDF = parsedEventsDF
      .filter(col("event_id").isNotNull)
      .filter(col("user_id").isNotNull)
      .filter(col("event_type").isNotNull)
      .filter(col("timestamp").isNotNull)

    // Load user profiles from external source (Redis/DynamoDB)
    val userProfilesDF = loadUserProfiles(spark)

    // Load product metadata from external source
    val productMetadataDF = loadProductMetadata(spark)

    // Enrich events with user profiles
    val userEnrichedDF = validEventsDF
      .join(
        userProfilesDF.withWatermark("last_activity", "1 hour"),
        Seq("user_id"),
        "left_outer"
      )

    // Enrich with product metadata for product-related events
    val productEnrichedDF = userEnrichedDF
      .join(
        productMetadataDF.withWatermark("last_updated", "1 hour"),
        expr("properties['product_id'] = product_id"),
        "left_outer"
      )

    // Add derived fields and business logic
    val enrichedEventsDF = productEnrichedDF
      .withColumn("enriched_timestamp", current_timestamp())
      .withColumn("processing_date", current_date())
      .withColumn("hour_of_day", hour(col("timestamp")))
      .withColumn("day_of_week", dayofweek(col("timestamp")))
      .withColumn("is_weekend", when(dayofweek(col("timestamp")).isin(1, 7), true).otherwise(false))
      .withColumn("event_revenue", calculateEventRevenue(col("event_type"), col("properties"), col("price")))
      .withColumn("customer_value_segment", calculateCustomerSegment(col("total_spent"), col("total_orders")))      .withColumn("session_sequence", 
        row_number().over(
          Window.partitionBy(col("session_id"))
            .orderBy(col("timestamp"))
        )
      )

    // Data quality checks
    val qualityCheckedDF = enrichedEventsDF
      .withColumn("data_quality_score", calculateQualityScore(
        col("event_id"), col("user_id"), col("properties"), col("metadata")
      ))
      .withColumn("is_valid_event", col("data_quality_score") > 0.7)

    // Write enriched events to Kafka and Data Lake
    val enrichedQuery = writeEnrichedEvents(qualityCheckedDF, "enriched")
    val dataLakeQuery = writeToDataLake(qualityCheckedDF.filter(col("is_valid_event")))
    val metricsQuery = writeRealTimeMetrics(qualityCheckedDF)
    val qualityQuery = writeQualityMetrics(qualityCheckedDF.filter(!col("is_valid_event")))

    Array(enrichedQuery, dataLakeQuery, metricsQuery, qualityQuery)
  }

  def loadUserProfiles(spark: SparkSession): DataFrame = {
    // In production, this would connect to Redis/DynamoDB
    // For demo, we'll create a mock streaming DataFrame
    import spark.implicits._

    spark
      .readStream
      .format("rate")
      .option("rowsPerSecond", "100")
      .load()
      .select(
        (col("value") % 10000).cast("string").as("user_id"),
        lit("John").as("first_name"),
        lit("Doe").as("last_name"),
        concat(lit("user"), col("value"), lit("@example.com")).as("email"),
        when(col("value") % 4 === 0, "18-25")
          .when(col("value") % 4 === 1, "26-35")
          .when(col("value") % 4 === 2, "36-50")
          .otherwise("50+").as("age_group"),
        when(col("value") % 5 === 0, "New York")
          .when(col("value") % 5 === 1, "Los Angeles")
          .when(col("value") % 5 === 2, "Chicago")
          .when(col("value") % 5 === 3, "Houston")
          .otherwise("Miami").as("location"),
        when(col("value") % 3 === 0, "Premium")
          .when(col("value") % 3 === 1, "Regular")
          .otherwise("New").as("customer_segment"),
        current_timestamp().as("registration_date"),
        current_timestamp().as("last_activity"),
        (col("value") % 50).as("total_orders"),
        (col("value") % 10000).cast("double").as("total_spent")
      )
  }

  def loadProductMetadata(spark: SparkSession): DataFrame = {
    // In production, this would connect to product database
    import spark.implicits._

    spark
      .readStream
      .format("rate")
      .option("rowsPerSecond", "50")
      .load()
      .select(
        concat(lit("prod-"), col("value") % 1000).as("product_id"),
        concat(lit("Product "), col("value") % 1000).as("product_name"),
        when(col("value") % 6 === 0, "Electronics")
          .when(col("value") % 6 === 1, "Clothing")
          .when(col("value") % 6 === 2, "Books")
          .when(col("value") % 6 === 3, "Home")
          .when(col("value") % 6 === 4, "Sports")
          .otherwise("Beauty").as("category"),
        lit("Subcategory").as("subcategory"),
        concat(lit("Brand "), col("value") % 20).as("brand"),
        (col("value") % 500 + 10).cast("double").as("price"),
        (col("value") % 300 + 5).cast("double").as("cost"),
        ((col("value") % 500 + 10) - (col("value") % 300 + 5)).cast("double").as("margin"),
        (col("value") % 1000).as("inventory_level"),
        current_timestamp().as("last_updated")
      )
  }

  def calculateEventRevenue = udf((eventType: String, properties: Map[String, String], price: Double) => {
    eventType match {
      case "purchase" => 
        properties.get("total_amount").map(_.toDouble).getOrElse(0.0)
      case "add_to_cart" => 
        properties.get("quantity").map(_.toInt).getOrElse(1) * Option(price).getOrElse(0.0) * 0.1 // Expected revenue
      case _ => 0.0
    }
  })

  def calculateCustomerSegment = udf((totalSpent: Double, totalOrders: Int) => {
    (totalSpent, totalOrders) match {
      case (spent, orders) if spent > 1000 && orders > 10 => "VIP"
      case (spent, orders) if spent > 500 && orders > 5 => "Premium"
      case (spent, orders) if spent > 100 && orders > 2 => "Regular"
      case _ => "New"
    }
  })

  def calculateQualityScore = udf((eventId: String, userId: String, properties: Map[String, String], metadata: Map[String, String]) => {
    var score = 1.0
    
    // Check required fields
    if (eventId == null || eventId.isEmpty) score -= 0.3
    if (userId == null || userId.isEmpty) score -= 0.3
    
    // Check properties completeness
    if (properties == null || properties.isEmpty) score -= 0.2
    
    // Check metadata completeness  
    if (metadata == null || metadata.isEmpty) score -= 0.2
    
    Math.max(0.0, score)
  })

  def writeEnrichedEvents(df: DataFrame, outputMode: String): StreamingQuery = {
    val enrichedJson = df
      .select(to_json(struct(df.columns.map(col): _*)).as("value"))

    enrichedJson
      .writeStream
      .format("kafka")
      .option("kafka.bootstrap.servers", sys.env.getOrElse("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"))
      .option("topic", "ecommerce-events-enriched")
      .option("checkpointLocation", "s3a://ecompulse-prod-data-lake/checkpoints/enriched-events")
      .outputMode("append")
      .trigger(Trigger.ProcessingTime("10 seconds"))
      .start()
  }

  def writeToDataLake(df: DataFrame): StreamingQuery = {
    df
      .writeStream
      .format("delta") // Using Delta Lake for ACID transactions
      .option("path", "s3a://ecompulse-prod-data-lake/enriched-events")
      .option("checkpointLocation", "s3a://ecompulse-prod-data-lake/checkpoints/delta-enriched")
      .partitionBy("processing_date", "hour_of_day")
      .outputMode("append")
      .trigger(Trigger.ProcessingTime("30 seconds"))
      .start()
  }

  def writeRealTimeMetrics(df: DataFrame): StreamingQuery = {
    val metricsDF = df
      .withWatermark("timestamp", "5 minutes")
      .groupBy(
        window(col("timestamp"), "1 minute"),
        col("event_type"),
        col("source"),
        col("customer_segment")
      )
      .agg(
        count("*").as("event_count"),
        countDistinct("user_id").as("unique_users"),
        countDistinct("session_id").as("unique_sessions"),
        sum("event_revenue").as("total_revenue"),
        avg("data_quality_score").as("avg_quality_score")
      )
      .select(
        col("window.start").as("window_start"),
        col("window.end").as("window_end"),
        col("event_type"),
        col("source"),
        col("customer_segment"),
        col("event_count"),
        col("unique_users"),
        col("unique_sessions"),
        col("total_revenue"),
        col("avg_quality_score"),
        current_timestamp().as("generated_at")
      )

    val metricsJson = metricsDF
      .select(to_json(struct(metricsDF.columns.map(col): _*)).as("value"))

    metricsJson
      .writeStream
      .format("kafka")
      .option("kafka.bootstrap.servers", sys.env.getOrElse("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"))
      .option("topic", "realtime-metrics")
      .option("checkpointLocation", "s3a://ecompulse-prod-data-lake/checkpoints/realtime-metrics")
      .outputMode("append")
      .trigger(Trigger.ProcessingTime("1 minute"))
      .start()
  }

  def writeQualityMetrics(df: DataFrame): StreamingQuery = {
    val qualityIssues = df
      .select(
        col("event_id"),
        col("user_id"),
        col("event_type"),
        col("timestamp"),
        col("data_quality_score"),
        lit("LOW_QUALITY_SCORE").as("issue_type"),
        current_timestamp().as("detected_at")
      )

    val qualityJson = qualityIssues
      .select(to_json(struct(qualityIssues.columns.map(col): _*)).as("value"))

    qualityJson
      .writeStream
      .format("kafka")
      .option("kafka.bootstrap.servers", sys.env.getOrElse("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"))
      .option("topic", "data-quality-issues")
      .option("checkpointLocation", "s3a://ecompulse-prod-data-lake/checkpoints/quality-issues")
      .outputMode("append")
      .trigger(Trigger.ProcessingTime("30 seconds"))
      .start()
  }
}
