# Apache Airflow DAGs & Data Quality

This module contains Apache Airflow DAGs for orchestrating the E-ComPulse data pipeline with comprehensive data quality validation using Great Expectations.

## Components

### 1. Data Pipeline Orchestration
- **Stream Processing Management**: Start/stop Spark streaming jobs
- **Batch Processing**: Daily aggregations and data warehouse updates
- **Data Quality Validation**: Schema, completeness, and business rule checks
- **External Dependencies**: API calls, file transfers, database updates

### 2. Data Quality Framework
- **Great Expectations Integration**: Automated data profiling and validation
- **Schema Evolution**: Automatic schema drift detection and adaptation
- **Business Rule Validation**: Custom validators for domain-specific rules
- **Data Lineage Tracking**: End-to-end data flow documentation

### 3. Monitoring & Alerting
- **SLA Monitoring**: Pipeline execution time and success rate tracking
- **Quality Alerts**: Slack/email notifications for data quality violations
- **Performance Metrics**: Task duration, resource utilization, and throughput
- **Incident Response**: Automated rollback and retry mechanisms

## DAG Structure

### Main Data Pipeline DAG
```
data_ingestion_dag
├── validate_kafka_connectivity
├── start_spark_enrichment_job
├── validate_enriched_data_quality
├── trigger_session_analytics
├── validate_session_metrics
├── update_data_warehouse
├── validate_warehouse_data
├── generate_business_reports
└── send_completion_notification
```

### Data Quality DAG
```
data_quality_dag
├── profile_raw_events
├── validate_schema_compliance
├── check_completeness_rates
├── validate_business_rules
├── detect_anomalies
├── update_data_catalog
└── generate_quality_report
```

## Great Expectations Configuration

### Expectation Suites
- **Raw Events Suite**: Basic schema and format validation
- **Enriched Events Suite**: Data enrichment quality checks
- **Business Metrics Suite**: KPI calculation validation
- **Data Warehouse Suite**: Final data quality validation

### Data Sources
- **Kafka Topics**: Real-time stream validation
- **S3 Data Lake**: Batch file validation
- **Redshift Tables**: Data warehouse validation
- **Redis Cache**: Lookup data validation

## Deployment

```bash
# Install dependencies
pip install -r requirements.txt

# Initialize Airflow database
airflow db init

# Create admin user
airflow users create --username admin --password admin --firstname Admin --lastname User --role Admin --email admin@ecompulse.com

# Start Airflow services
airflow webserver --port 8080 &
airflow scheduler &

# Deploy DAGs
cp dags/*.py $AIRFLOW_HOME/dags/
```

## Configuration

### Environment Variables
```bash
AIRFLOW__CORE__EXECUTOR=KubernetesExecutor
AIRFLOW__KUBERNETES__NAMESPACE=airflow
AIRFLOW__CORE__SQL_ALCHEMY_CONN=postgresql://airflow:password@postgres:5432/airflow
AIRFLOW__CORE__FERNET_KEY=<generated-key>
KAFKA_BOOTSTRAP_SERVERS=kafka-service:9092
SPARK_OPERATOR_NAMESPACE=spark-jobs
GREAT_EXPECTATIONS_CONFIG_DIR=/opt/airflow/great_expectations
```

### Custom Operators
- **SparkKubernetesOperator**: Submit Spark jobs to Kubernetes
- **GreatExpectationsOperator**: Run data quality validations
- **KafkaTopicOperator**: Manage Kafka topics and consumer groups
- **SlackNotificationOperator**: Send alerts and notifications
