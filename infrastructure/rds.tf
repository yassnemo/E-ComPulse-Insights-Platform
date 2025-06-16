# RDS Instance for Airflow Metadata Database

# Random password for RDS
resource "random_password" "rds_password" {
  length  = 16
  special = true
}

# AWS Secrets Manager secret for RDS password
resource "aws_secretsmanager_secret" "rds_password" {
  name                    = "${var.project_name}-${var.environment}-rds-password"
  description             = "RDS password for Airflow metadata database"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-secret"
  }
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id = aws_secretsmanager_secret.rds_password.id
  secret_string = jsonencode({
    username = "airflow"
    password = random_password.rds_password.result
  })
}

# DB subnet group
resource "aws_db_subnet_group" "airflow" {
  name       = "${var.project_name}-${var.environment}-airflow"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "${var.project_name}-${var.environment}-airflow-subnet-group"
  }
}

# RDS parameter group for PostgreSQL optimization
resource "aws_db_parameter_group" "airflow" {
  family = "postgres15"
  name   = "${var.project_name}-${var.environment}-airflow-params"

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "max_connections"
    value = "200"
  }

  parameter {
    name  = "work_mem"
    value = "4096"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-airflow-params"
  }
}

# RDS instance
resource "aws_db_instance" "airflow" {
  identifier = "${var.project_name}-${var.environment}-airflow"

  # Engine configuration
  engine         = "postgres"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  # Storage configuration
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_allocated_storage * 2
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database configuration
  db_name  = "airflow"
  username = "airflow"
  password = random_password.rds_password.result
  port     = 5432

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.airflow.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Parameter group
  parameter_group_name = aws_db_parameter_group.airflow.name

  # Backup configuration
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  # Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Performance insights
  performance_insights_enabled = true

  # Deletion protection
  deletion_protection = var.environment == "prod" ? true : false
  skip_final_snapshot = var.environment == "prod" ? false : true

  # Enable automatic minor version upgrades
  auto_minor_version_upgrade = true

  # Enable multi-AZ for production
  multi_az = var.environment == "prod" ? true : false

  tags = {
    Name = "${var.project_name}-${var.environment}-airflow-db"
  }
}

# IAM role for RDS monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
