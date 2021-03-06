data "aws_vpc" "selected" {
  filter {
    name = "tag:ClusterId"
    values = [var.eks_cluster_id]
  }
}

data "aws_subnet_ids" "k8s_subnet_ids" {
  vpc_id = data.aws_vpc.selected.id
  filter {
    name = "tag:ClusterId"
    values = [var.eks_cluster_id]
  }
  filter {
    name = "tag:Service"
    values = ["RDS"]
  }
}

data "aws_security_group" "selected" {
  filter {
    name = "tag:Name"
    values = ["qovery-eks-workers"]
  }
  filter {
    name   = "tag:kubernetes.io/cluster/${var.eks_cluster_id}"
    values = ["owned"]
  }
}

data "aws_iam_role" "rds_enhanced_monitoring" {
  name = "qovery-rds-enhanced-monitoring-${var.eks_cluster_id}"
}

resource "helm_release" "mysql_instance_external_name" {
  name = "${aws_db_instance.mysql_instance.id}-externalname"
  chart = "external-name-svc"
  namespace = "{{namespace}}"
  atomic = true
  max_history = 50

  set {
    name = "target_hostname"
    value = aws_db_instance.mysql_instance.address
  }
  set {
    name = "source_fqdn"
    value = "{{database_fqdn}}"
  }
  set {
    name = "app_id"
    value = "{{database_id}}"
  }

  depends_on = [
    aws_db_instance.mysql_instance
  ]
}

# Non snapshoted version
resource "aws_db_instance" "mysql_instance" {
  identifier = var.mysql_identifier

  tags = {
    cluster_name = var.cluster_name
    cluster_id = var.eks_cluster_id
    region = var.region
    q_client_id = var.q_customer_id
    q_environment_id = var.q_environment_id
    q_project_id = var.q_project_id
    database_identifier = var.mysql_identifier
    {% if snapshot is defined and snapshot["snapshot_id"] %}meta_last_restored_from = var.snapshot_identifier{% endif %}
  }

  # MySQL instance basics
  instance_class = var.instance_class
  port = var.port
  timeouts {
    create = "60m"
    update = "120m"
    delete = "60m"
  }
  password = var.password
  {%- if snapshot is defined and snapshot["snapshot_id"] %}
  # Snapshot
  snapshot_identifier = var.snapshot_identifier
  {%- else %}
  allocated_storage = var.disk_size
  storage_type = var.storage_type
  username = var.username
  engine_version = var.mysql_version
  engine = "mysql"
  ca_cert_identifier = "rds-ca-2019"
  {%- endif %}

  # Network
  db_subnet_group_name = data.aws_subnet_ids.k8s_subnet_ids.id
  vpc_security_group_ids = data.aws_security_group.selected.*.id
  publicly_accessible = var.publicly_accessible
  multi_az = var.multi_az

  # Maintenance and upgrades
  apply_immediately = var.apply_changes_now
  auto_minor_version_upgrade = var.upgrade_minor
  maintenance_window = var.maintenance_window

  # Monitoring
  monitoring_interval = 10
  monitoring_role_arn = data.aws_iam_role.rds_enhanced_monitoring.arn

  # Backups
  backup_retention_period = var.backup_retention_period
  backup_window = var.backup_window
  skip_final_snapshot = true
  delete_automated_backups = false

}