# Aurora Global Database for the critical data set (docs/01-reliability-model.md section 5).
# Primary: t1dx-aurora-apse5 (writer + reader, Multi-AZ). Secondary: t1dx-aurora-apse1.
# RPO: storage-level async replication, typically < 1 s; alarmed via AuroraGlobalDBRPOLag
# (published by the secondary cluster only, see terraform/observability/slo_burn_rate_alarms.tf).
# rds.global_db_rpo is intentionally NOT set (see docs/05-dr-runbook.md section 10).

resource "aws_kms_key" "aurora" {
  provider                = aws.apse5
  description             = "t1dx Aurora encryption (multi-Region primary)"
  multi_region            = true
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "aurora_apse5" {
  provider      = aws.apse5
  name          = "alias/t1dx-aurora"
  target_key_id = aws_kms_key.aurora.key_id
}

resource "aws_kms_replica_key" "aurora_apse1" {
  provider                = aws.apse1
  description             = "t1dx Aurora encryption (multi-Region replica)"
  primary_key_arn         = aws_kms_key.aurora.arn
  deletion_window_in_days = 30
}

resource "aws_rds_global_cluster" "this" {
  provider                  = aws.apse5
  global_cluster_identifier = "t1dx-aurora-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.aurora_engine_version
  storage_encrypted         = true
  deletion_protection       = true
}

resource "aws_rds_cluster" "apse5" {
  provider                        = aws.apse5
  cluster_identifier              = "t1dx-aurora-apse5"
  global_cluster_identifier       = aws_rds_global_cluster.this.id
  engine                          = aws_rds_global_cluster.this.engine
  engine_version                  = aws_rds_global_cluster.this.engine_version
  database_name                   = "t1dx"
  master_username                 = "t1dx_admin"
  master_password                 = var.db_master_password
  db_subnet_group_name            = var.db_subnet_group["apse5"]
  vpc_security_group_ids          = var.db_security_group_ids["apse5"]
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.aurora.arn
  backup_retention_period         = 35
  copy_tags_to_snapshot           = true
  deletion_protection             = true
  enabled_cloudwatch_logs_exports = ["postgresql"]

  iam_database_authentication_enabled = true

  lifecycle {
    # After a switchover/failover the roles swap; don't let Terraform fight the topology.
    ignore_changes = [global_cluster_identifier, replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "apse5" {
  for_each = {
    writer = "ap-southeast-5a"
    reader = "ap-southeast-5b"
  }

  provider                     = aws.apse5
  identifier                   = "t1dx-aurora-apse5-${each.key}"
  cluster_identifier           = aws_rds_cluster.apse5.id
  engine                       = aws_rds_cluster.apse5.engine
  engine_version               = aws_rds_cluster.apse5.engine_version
  instance_class               = var.aurora_instance_class
  availability_zone            = each.value
  performance_insights_enabled = true
  auto_minor_version_upgrade   = false # keep both Regions on identical versions
}

resource "aws_rds_cluster" "apse1" {
  provider                  = aws.apse1
  cluster_identifier        = "t1dx-aurora-apse1"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  db_subnet_group_name      = var.db_subnet_group["apse1"]
  vpc_security_group_ids    = var.db_security_group_ids["apse1"]
  storage_encrypted         = true
  kms_key_id                = aws_kms_replica_key.aurora_apse1.arn
  backup_retention_period   = 35
  copy_tags_to_snapshot     = true
  deletion_protection       = true

  iam_database_authentication_enabled = true

  depends_on = [aws_rds_cluster_instance.apse5]

  lifecycle {
    ignore_changes = [global_cluster_identifier, replication_source_identifier]
  }
}

# One instance in the secondary so it can be promoted immediately; Region switch
# "Aurora Provisioned Scaling" adds a reader and matches the primary's class on activation.
resource "aws_rds_cluster_instance" "apse1" {
  provider                     = aws.apse1
  identifier                   = "t1dx-aurora-apse1-writer-ready"
  cluster_identifier           = aws_rds_cluster.apse1.id
  engine                       = aws_rds_cluster.apse1.engine
  engine_version               = aws_rds_cluster.apse1.engine_version
  instance_class               = var.aurora_instance_class
  availability_zone            = "ap-southeast-1a"
  performance_insights_enabled = true
  auto_minor_version_upgrade   = false
}
