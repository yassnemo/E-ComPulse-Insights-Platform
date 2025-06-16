"""
Main Data Pipeline DAG for E-ComPulse Platform

This DAG orchestrates the complete data pipeline from raw event ingestion
through real-time processing to data warehouse updates with comprehensive
data quality validation at each stage.

Schedule: Every hour
Owner: Data Engineering Team
Tags: ['ecommerce', 'real-time', 'data-quality']
"""

from datetime import datetime, timedelta
from typing import Dict, Any

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.providers.postgres.operators.postgres import PostgresOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.providers.amazon.aws.operators.s3 import S3ListOperator
from airflow.providers.slack.operators.slack_webhook import SlackWebhookOperator
from airflow.sensors.s3_key_sensor import S3KeySensor
from airflow.sensors.external_task_sensor import ExternalTaskSensor
from airflow.utils.dates import days_ago
from airflow.utils.trigger_rule import TriggerRule
from airflow.models import Variable

# Custom operators
from operators.spark_kubernetes_operator import SparkKubernetesOperator
from operators.great_expectations_operator import GreatExpectationsOperator
from operators.kafka_operator import KafkaHealthCheckOperator, KafkaConsumerLagOperator
from operators.redshift_operator import RedshiftDataQualityOperator

# Default arguments
default_args = {
    'owner': 'data-engineering',
    'depends_on_past': False,
    'start_date': days_ago(1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
    'max_active_runs': 1,
    'catchup': False
}

# DAG definition
dag = DAG(
    'ecommerce_data_pipeline',
    default_args=default_args,
    description='E-ComPulse real-time data pipeline with quality validation',
    schedule_interval=timedelta(hours=1),
    max_active_runs=1,
    tags=['ecommerce', 'real-time', 'data-quality'],
    doc_md=__doc__
)

# Configuration
KAFKA_BOOTSTRAP_SERVERS = Variable.get("kafka_bootstrap_servers", "kafka-service:9092")
SPARK_NAMESPACE = Variable.get("spark_namespace", "spark-jobs")
S3_BUCKET = Variable.get("s3_data_lake_bucket", "ecompulse-prod-data-lake")
REDSHIFT_CONN_ID = Variable.get("redshift_conn_id", "redshift_default")
SLACK_WEBHOOK_CONN_ID = Variable.get("slack_webhook_conn_id", "slack_default")

def check_data_freshness(**context):
    """Check if new data is available in the last hour"""
    from airflow.providers.postgres.hooks.postgres import PostgresHook
    
    pg_hook = PostgresHook(postgres_conn_id='metadata_db')
    
    # Check latest event timestamp in raw events topic
    query = """
    SELECT 
        COUNT(*) as event_count,
        MAX(event_timestamp) as latest_event
    FROM kafka_consumer_offsets 
    WHERE topic = 'ecommerce-events-raw'
    AND partition_timestamp >= NOW() - INTERVAL '1 hour'
    """
    
    result = pg_hook.get_first(query)
    event_count, latest_event = result
    
    if event_count == 0:
        raise ValueError("No new events found in the last hour")
    
    context['task_instance'].xcom_push(key='event_count', value=event_count)
    context['task_instance'].xcom_push(key='latest_event', value=str(latest_event))
    
    return f"Found {event_count} new events, latest: {latest_event}"

def validate_upstream_dependencies(**context):
    """Validate all upstream systems are healthy"""
    import requests
    import json
    
    checks = []
    
    # Check Kafka cluster health
    try:
        kafka_check = requests.get(f"http://kafka-rest-proxy:8082/topics", timeout=30)
        checks.append({"service": "kafka", "status": "healthy" if kafka_check.status_code == 200 else "unhealthy"})
    except Exception as e:
        checks.append({"service": "kafka", "status": "unhealthy", "error": str(e)})
    
    # Check Spark cluster health
    try:
        spark_check = requests.get(f"http://spark-master:8080/api/v1/applications", timeout=30)
        checks.append({"service": "spark", "status": "healthy" if spark_check.status_code == 200 else "unhealthy"})
    except Exception as e:
        checks.append({"service": "spark", "status": "unhealthy", "error": str(e)})
    
    # Check Redis health
    try:
        import redis
        r = redis.Redis(host='redis-service', port=6379, db=0)
        r.ping()
        checks.append({"service": "redis", "status": "healthy"})
    except Exception as e:
        checks.append({"service": "redis", "status": "unhealthy", "error": str(e)})
    
    # Fail if any critical service is unhealthy
    unhealthy_services = [check for check in checks if check["status"] == "unhealthy"]
    if unhealthy_services:
        raise ValueError(f"Unhealthy upstream services: {unhealthy_services}")
    
    context['task_instance'].xcom_push(key='health_checks', value=checks)
    return checks

def calculate_processing_metrics(**context):
    """Calculate processing metrics for monitoring"""
    ti = context['task_instance']
    
    # Get event count from upstream task
    event_count = ti.xcom_pull(task_ids='check_data_freshness', key='event_count')
    
    # Calculate expected processing time based on event volume
    base_processing_time = 300  # 5 minutes base
    additional_time = (event_count // 10000) * 60  # 1 minute per 10k events
    expected_duration = base_processing_time + additional_time
    
    # Set dynamic timeouts for downstream tasks
    context['task_instance'].xcom_push(key='expected_duration', value=expected_duration)
    context['task_instance'].xcom_push(key='timeout_seconds', value=expected_duration + 300)
    
    return {
        'event_count': event_count,
        'expected_duration': expected_duration,
        'timeout_seconds': expected_duration + 300
    }

# Task 1: Validate upstream dependencies
validate_dependencies = PythonOperator(
    task_id='validate_upstream_dependencies',
    python_callable=validate_upstream_dependencies,
    dag=dag,
    doc_md="Validate all upstream systems (Kafka, Spark, Redis) are healthy"
)

# Task 2: Check data freshness
check_freshness = PythonOperator(
    task_id='check_data_freshness',
    python_callable=check_data_freshness,
    dag=dag,
    doc_md="Check if new data is available for processing"
)

# Task 3: Kafka health check
kafka_health_check = KafkaHealthCheckOperator(
    task_id='kafka_health_check',
    kafka_bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
    topics=['ecommerce-events-raw', 'ecommerce-events-enriched'],
    dag=dag
)

# Task 4: Check consumer lag
check_consumer_lag = KafkaConsumerLagOperator(
    task_id='check_consumer_lag',
    kafka_bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
    consumer_group='spark-enrichment-consumer',
    max_lag_threshold=10000,
    dag=dag
)

# Task 5: Calculate processing metrics
calc_metrics = PythonOperator(
    task_id='calculate_processing_metrics',
    python_callable=calculate_processing_metrics,
    dag=dag
)

# Task 6: Start Spark event enrichment job
start_enrichment_job = SparkKubernetesOperator(
    task_id='start_spark_enrichment_job',
    application_file='local:///opt/spark-apps/ecompulse-streaming-1.0.0-assembly.jar',
    main_class='com.ecompulse.streaming.EventEnrichmentJob',
    name='event-enrichment-{{ ds }}-{{ ts_nodash }}',
    namespace=SPARK_NAMESPACE,
    driver_memory='2g',
    driver_cores=1,
    executor_memory='4g',
    executor_cores=2,
    num_executors=3,
    conf={
        'spark.sql.adaptive.enabled': 'true',
        'spark.sql.adaptive.coalescePartitions.enabled': 'true',
        'spark.kubernetes.executor.deleteOnTermination': 'true'
    },
    env_vars={
        'KAFKA_BOOTSTRAP_SERVERS': KAFKA_BOOTSTRAP_SERVERS,
        'S3_BUCKET': S3_BUCKET
    },
    dag=dag
)

# Task 7: Validate enriched data quality
validate_enriched_data = GreatExpectationsOperator(
    task_id='validate_enriched_data_quality',
    data_context_dir='/opt/airflow/great_expectations',
    checkpoint_name='enriched_events_checkpoint',
    expectation_suite_name='enriched_events_suite',
    batch_request={
        'datasource_name': 'kafka_datasource',
        'data_connector_name': 'default_runtime_data_connector',
        'data_asset_name': 'ecommerce-events-enriched',
        'runtime_parameters': {
            'batch_identifiers': {
                'pipeline_run_id': '{{ ds }}_{{ ts_nodash }}'
            }
        }
    },
    dag=dag
)

# Task 8: Start session analytics job
start_session_analytics = SparkKubernetesOperator(
    task_id='start_session_analytics_job',
    application_file='local:///opt/spark-apps/ecompulse-streaming-1.0.0-assembly.jar',
    main_class='com.ecompulse.streaming.SessionAnalyticsJob',
    name='session-analytics-{{ ds }}-{{ ts_nodash }}',
    namespace=SPARK_NAMESPACE,
    driver_memory='2g',
    driver_cores=1,
    executor_memory='4g',
    executor_cores=2,
    num_executors=2,
    env_vars={
        'KAFKA_BOOTSTRAP_SERVERS': KAFKA_BOOTSTRAP_SERVERS,
        'S3_BUCKET': S3_BUCKET
    },
    dag=dag
)

# Task 9: Update data warehouse
update_data_warehouse = PostgresOperator(
    task_id='update_data_warehouse',
    postgres_conn_id=REDSHIFT_CONN_ID,
    sql="""
    -- Upsert enriched events to data warehouse
    BEGIN;
    
    -- Create staging table
    CREATE TEMP TABLE staging_events AS 
    SELECT * FROM events WHERE 1=0;
    
    -- Load new data from S3
    COPY staging_events 
    FROM 's3://{{ var.value.s3_data_lake_bucket }}/enriched-events/processing_date={{ ds }}'
    IAM_ROLE '{{ var.value.redshift_iam_role }}'
    FORMAT AS PARQUET;
    
    -- Update existing records
    UPDATE events 
    SET 
        event_type = staging.event_type,
        properties = staging.properties,
        customer_segment = staging.customer_segment,
        event_revenue = staging.event_revenue,
        updated_at = CURRENT_TIMESTAMP
    FROM staging_events staging
    WHERE events.event_id = staging.event_id;
    
    -- Insert new records
    INSERT INTO events
    SELECT * FROM staging_events
    WHERE event_id NOT IN (SELECT event_id FROM events);
    
    -- Update summary tables
    REFRESH MATERIALIZED VIEW daily_metrics;
    REFRESH MATERIALIZED VIEW user_segments;
    
    COMMIT;
    """,
    dag=dag
)

# Task 10: Validate data warehouse quality
validate_warehouse_data = RedshiftDataQualityOperator(
    task_id='validate_warehouse_data_quality',
    redshift_conn_id=REDSHIFT_CONN_ID,
    table_name='events',
    quality_checks=[
        {
            'check_sql': 'SELECT COUNT(*) FROM events WHERE processing_date = \'{{ ds }}\'',
            'expected_result': lambda x: x > 0,
            'description': 'Events loaded for current date'
        },
        {
            'check_sql': 'SELECT COUNT(*) FROM events WHERE event_id IS NULL',
            'expected_result': 0,
            'description': 'No null event IDs'
        },
        {
            'check_sql': 'SELECT COUNT(DISTINCT user_id) FROM events WHERE processing_date = \'{{ ds }}\'',
            'expected_result': lambda x: x > 10,
            'description': 'Multiple unique users'
        }
    ],
    dag=dag
)

# Task 11: Generate business reports
generate_reports = PostgresOperator(
    task_id='generate_business_reports',
    postgres_conn_id=REDSHIFT_CONN_ID,
    sql="""
    -- Generate daily business summary
    INSERT INTO daily_summary (
        report_date,
        total_events,
        unique_users,
        total_revenue,
        conversion_rate,
        avg_session_duration,
        created_at
    )
    SELECT 
        '{{ ds }}'::date,
        COUNT(*) as total_events,
        COUNT(DISTINCT user_id) as unique_users,
        SUM(event_revenue) as total_revenue,
        COUNT(CASE WHEN event_type = 'purchase' THEN 1 END)::float / 
        COUNT(CASE WHEN event_type = 'add_to_cart' THEN 1 END) as conversion_rate,
        AVG(session_duration_minutes) as avg_session_duration,
        CURRENT_TIMESTAMP
    FROM events e
    LEFT JOIN user_sessions s ON e.session_id = s.session_id
    WHERE e.processing_date = '{{ ds }}'::date;
    """,
    dag=dag
)

# Task 12: Data quality summary report
quality_summary = GreatExpectationsOperator(
    task_id='generate_quality_summary',
    data_context_dir='/opt/airflow/great_expectations',
    checkpoint_name='daily_quality_summary_checkpoint',
    expectation_suite_name='daily_summary_suite',
    dag=dag
)

# Task 13: Success notification
success_notification = SlackWebhookOperator(
    task_id='send_success_notification',
    http_conn_id=SLACK_WEBHOOK_CONN_ID,
    message="""
    ✅ *E-ComPulse Data Pipeline Completed Successfully*
    
    *Date:* {{ ds }}
    *Duration:* {{ (ti.end_date - ti.start_date).total_seconds() / 60 }} minutes
    *Events Processed:* {{ ti.xcom_pull(task_ids='check_data_freshness', key='event_count') }}
    
    *Quality Metrics:*
    • Raw data validation: ✅ Passed
    • Enrichment quality: ✅ Passed  
    • Warehouse validation: ✅ Passed
    
    Pipeline run: `{{ run_id }}`
    """,
    dag=dag,
    trigger_rule=TriggerRule.ALL_SUCCESS
)

# Task 14: Failure notification
failure_notification = SlackWebhookOperator(
    task_id='send_failure_notification',
    http_conn_id=SLACK_WEBHOOK_CONN_ID,
    message="""
    ❌ *E-ComPulse Data Pipeline Failed*
    
    *Date:* {{ ds }}
    *Failed Task:* {{ ti.task_id }}
    *Error:* {{ ti.log_url }}
    
    Please check the Airflow logs for details.
    Pipeline run: `{{ run_id }}`
    """,
    dag=dag,
    trigger_rule=TriggerRule.ONE_FAILED
)

# Define task dependencies
validate_dependencies >> check_freshness
check_freshness >> [kafka_health_check, check_consumer_lag]
[kafka_health_check, check_consumer_lag] >> calc_metrics
calc_metrics >> start_enrichment_job
start_enrichment_job >> validate_enriched_data
validate_enriched_data >> start_session_analytics
start_session_analytics >> update_data_warehouse
update_data_warehouse >> validate_warehouse_data
validate_warehouse_data >> generate_reports
generate_reports >> quality_summary
quality_summary >> success_notification

# Failure handling
[validate_dependencies, check_freshness, kafka_health_check, check_consumer_lag, 
 calc_metrics, start_enrichment_job, validate_enriched_data, start_session_analytics,
 update_data_warehouse, validate_warehouse_data, generate_reports, quality_summary] >> failure_notification
