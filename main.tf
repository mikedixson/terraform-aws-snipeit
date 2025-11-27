# Set your URL here
locals {
  app_name = "assets-inventory-company"
  app_url  = "https://assets.inventory.company.com"

  common_tags = {
    GitOps      = "Terraformed"
    Application = "Snipe-IT"
  }
}

# Data source to get current AWS region
data "aws_region" "current" {}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

#------------------------------------------------------------------------------
# VPC and Networking
#------------------------------------------------------------------------------

# VPC
resource "aws_vpc" "assets_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "assets-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "assets_igw" {
  vpc_id = aws_vpc.assets_vpc.id

  tags = merge(local.common_tags, {
    Name = "assets-igw"
  })
}

# Public Subnet for ALB
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.assets_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "assets-public-subnet-1"
  })
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.assets_vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "assets-public-subnet-2"
  })
}

# Private Subnet for ECS
resource "aws_subnet" "ecs_subnet" {
  vpc_id            = aws_vpc.assets_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(local.common_tags, {
    Name = "assets-ecs-subnet"
  })
}

# Private Subnet for ECS (second AZ for high availability)
resource "aws_subnet" "ecs_subnet_2" {
  vpc_id            = aws_vpc.assets_vpc.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = merge(local.common_tags, {
    Name = "assets-ecs-subnet-2"
  })
}

# Private Subnet for RDS MySQL
resource "aws_subnet" "mysql_subnet_1" {
  vpc_id            = aws_vpc.assets_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(local.common_tags, {
    Name = "assets-mysql-subnet-1"
  })
}

resource "aws_subnet" "mysql_subnet_2" {
  vpc_id            = aws_vpc.assets_vpc.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = merge(local.common_tags, {
    Name = "assets-mysql-subnet-2"
  })
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "assets-nat-eip"
  })

  depends_on = [aws_internet_gateway.assets_igw]
}

# NAT Gateway for private subnets
resource "aws_nat_gateway" "assets_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_1.id

  tags = merge(local.common_tags, {
    Name = "assets-nat-gateway"
  })

  depends_on = [aws_internet_gateway.assets_igw]
}

# Route Table for public subnets
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.assets_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.assets_igw.id
  }

  tags = merge(local.common_tags, {
    Name = "assets-public-rt"
  })
}

# Route Table for private subnets
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.assets_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.assets_nat.id
  }

  tags = merge(local.common_tags, {
    Name = "assets-private-rt"
  })
}

# Route table associations
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "ecs_1" {
  subnet_id      = aws_subnet.ecs_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "ecs_2" {
  subnet_id      = aws_subnet.ecs_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "mysql_1" {
  subnet_id      = aws_subnet.mysql_subnet_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "mysql_2" {
  subnet_id      = aws_subnet.mysql_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}

#------------------------------------------------------------------------------
# Security Groups
#------------------------------------------------------------------------------

# Security Group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "assets-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.assets_vpc.id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "assets-alb-sg"
  })
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_sg" {
  name        = "assets-ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.assets_vpc.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "assets-ecs-sg"
  })
}

# Security Group for RDS MySQL
resource "aws_security_group" "mysql_sg" {
  name        = "assets-mysql-sg"
  description = "Security group for RDS MySQL"
  vpc_id      = aws_vpc.assets_vpc.id

  ingress {
    description     = "MySQL from ECS"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "assets-mysql-sg"
  })
}

# Security Group for EFS
resource "aws_security_group" "efs_sg" {
  name        = "assets-efs-sg"
  description = "Security group for EFS"
  vpc_id      = aws_vpc.assets_vpc.id

  ingress {
    description     = "NFS from ECS"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "assets-efs-sg"
  })
}

#------------------------------------------------------------------------------
# AWS Secrets Manager (equivalent to Azure Key Vault)
#------------------------------------------------------------------------------

# Secret for DB Admin Password
resource "aws_secretsmanager_secret" "db_admin_password" {
  name                    = "assets-inventory/db-admin-password"
  recovery_window_in_days = 7

  tags = local.common_tags
}

# Note: You must set the secret value manually or via AWS CLI after creation
# aws secretsmanager put-secret-value --secret-id assets-inventory/db-admin-password --secret-string "your-password"

# Secret for App Key
resource "aws_secretsmanager_secret" "app_key" {
  name                    = "assets-inventory/app-key"
  recovery_window_in_days = 7

  tags = local.common_tags
}

# Secret for SendGrid API Key
resource "aws_secretsmanager_secret" "sendgrid_api_key" {
  name                    = "assets-inventory/sendgrid-api-key"
  recovery_window_in_days = 7

  tags = local.common_tags
}

# Data sources to read secret values (secrets must be populated first)
data "aws_secretsmanager_secret_version" "db_admin_password" {
  secret_id  = aws_secretsmanager_secret.db_admin_password.id
  depends_on = [aws_secretsmanager_secret.db_admin_password]
}

data "aws_secretsmanager_secret_version" "app_key" {
  secret_id  = aws_secretsmanager_secret.app_key.id
  depends_on = [aws_secretsmanager_secret.app_key]
}

data "aws_secretsmanager_secret_version" "sendgrid_api_key" {
  secret_id  = aws_secretsmanager_secret.sendgrid_api_key.id
  depends_on = [aws_secretsmanager_secret.sendgrid_api_key]
}

#------------------------------------------------------------------------------
# RDS MySQL (equivalent to Azure MySQL Flexible Server)
#------------------------------------------------------------------------------

# DB Subnet Group
resource "aws_db_subnet_group" "mysql_subnet_group" {
  name       = "assets-mysql-subnet-group"
  subnet_ids = [aws_subnet.mysql_subnet_1.id, aws_subnet.mysql_subnet_2.id]

  tags = merge(local.common_tags, {
    Name = "assets-mysql-subnet-group"
  })
}

# RDS Parameter Group for MySQL configuration
resource "aws_db_parameter_group" "mysql_params" {
  family = "mysql8.0"
  name   = "assets-mysql-params"

  parameter {
    name  = "innodb_buffer_pool_load_at_startup"
    value = "0"
  }

  parameter {
    name  = "innodb_buffer_pool_dump_at_shutdown"
    value = "0"
  }

  parameter {
    name  = "sql_generate_invisible_primary_key"
    value = "0"
  }

  tags = local.common_tags
}

# RDS MySQL Instance
resource "aws_db_instance" "assets_inventory_db" {
  identifier     = "assets-inventory-db"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "snipeit"
  username = "assetsadmin"
  password = data.aws_secretsmanager_secret_version.db_admin_password.secret_string

  db_subnet_group_name   = aws_db_subnet_group.mysql_subnet_group.name
  vpc_security_group_ids = [aws_security_group.mysql_sg.id]
  parameter_group_name   = aws_db_parameter_group.mysql_params.name

  multi_az            = false
  publicly_accessible = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  skip_final_snapshot       = false
  final_snapshot_identifier = "assets-inventory-db-final-snapshot"
  deletion_protection       = true

  tags = merge(local.common_tags, {
    Name = "assets-inventory-db"
  })
}

#------------------------------------------------------------------------------
# EFS (equivalent to Azure Storage Account File Shares)
#------------------------------------------------------------------------------

# EFS File System for Snipe-IT data
resource "aws_efs_file_system" "snipeit_efs" {
  creation_token = "snipeit-efs"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(local.common_tags, {
    Name = "snipeit-efs"
  })
}

# EFS Mount Targets
resource "aws_efs_mount_target" "snipeit_efs_mount_1" {
  file_system_id  = aws_efs_file_system.snipeit_efs.id
  subnet_id       = aws_subnet.ecs_subnet.id
  security_groups = [aws_security_group.efs_sg.id]
}

resource "aws_efs_mount_target" "snipeit_efs_mount_2" {
  file_system_id  = aws_efs_file_system.snipeit_efs.id
  subnet_id       = aws_subnet.ecs_subnet_2.id
  security_groups = [aws_security_group.efs_sg.id]
}

# EFS Access Points
resource "aws_efs_access_point" "snipeit_data" {
  file_system_id = aws_efs_file_system.snipeit_efs.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/snipeit-data"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = merge(local.common_tags, {
    Name = "snipeit-data-ap"
  })
}

resource "aws_efs_access_point" "snipeit_logs" {
  file_system_id = aws_efs_file_system.snipeit_efs.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/snipeit-logs"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = merge(local.common_tags, {
    Name = "snipeit-logs-ap"
  })
}

#------------------------------------------------------------------------------
# ECS Cluster and Service (equivalent to Azure App Service)
#------------------------------------------------------------------------------

# ECS Cluster
resource "aws_ecs_cluster" "assets_cluster" {
  name = "assets-inventory-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/snipeit"
  retention_in_days = 30

  tags = local.common_tags
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "assets-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Policy for Secrets Manager access
resource "aws_iam_role_policy" "ecs_secrets_policy" {
  name = "assets-ecs-secrets-policy"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.db_admin_password.arn,
          aws_secretsmanager_secret.app_key.arn,
          aws_secretsmanager_secret.sendgrid_api_key.arn
        ]
      }
    ]
  })
}

# IAM Role for ECS Task
resource "aws_iam_role" "ecs_task_role" {
  name = "assets-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Policy for EFS access from ECS task
resource "aws_iam_role_policy" "ecs_efs_policy" {
  name = "assets-ecs-efs-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.snipeit_efs.arn
      }
    ]
  })
}

# ECS Task Definition
resource "aws_ecs_task_definition" "snipeit" {
  family                   = "snipeit"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "snipeit"
      image     = "snipe/snipe-it:latest"
      essential = true

      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "APP_URL", value = local.app_url },
        { name = "APP_TIMEZONE", value = "America/Vancouver" },
        { name = "APP_ENV", value = "production" },
        { name = "APP_DEBUG", value = "false" },
        { name = "APP_LOCALE", value = "en-US" },
        { name = "MYSQL_DATABASE", value = "snipeit" },
        { name = "MYSQL_USER", value = "assetsadmin" },
        { name = "DB_CONNECTION", value = "mysql" },
        { name = "MYSQL_PORT_3306_TCP_ADDR", value = aws_db_instance.assets_inventory_db.address },
        { name = "MYSQL_PORT_3306_TCP_PORT", value = "3306" },
        { name = "DB_SSL", value = "true" },
        { name = "MAIL_DRIVER", value = "smtp" },
        { name = "MAIL_ENV_ENCRYPTION", value = "tls" },
        { name = "MAIL_PORT_587_TCP_ADDR", value = "smtp.sendgrid.net" },
        { name = "MAIL_PORT_587_TCP_PORT", value = "587" },
        { name = "MAIL_ENV_USERNAME", value = "apikey" },
        { name = "MAIL_ENV_FROM_ADDR", value = "assetsadmins@company.com" },
        { name = "MAIL_ENV_FROM_NAME", value = "Assets Admins" },
        { name = "SCIM_STANDARDS_COMPLIANCE", value = "true" },
        { name = "SCIM_TRACE", value = "false" }
      ]

      secrets = [
        {
          name      = "APP_KEY"
          valueFrom = aws_secretsmanager_secret.app_key.arn
        },
        {
          name      = "MYSQL_PASSWORD"
          valueFrom = aws_secretsmanager_secret.db_admin_password.arn
        },
        {
          name      = "MAIL_ENV_PASSWORD"
          valueFrom = aws_secretsmanager_secret.sendgrid_api_key.arn
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "snipeit-data"
          containerPath = "/var/lib/snipeit"
          readOnly      = false
        },
        {
          sourceVolume  = "snipeit-logs"
          containerPath = "/var/www/html/storage/logs"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "snipeit"
        }
      }
    }
  ])

  volume {
    name = "snipeit-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.snipeit_efs.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.snipeit_data.id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "snipeit-logs"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.snipeit_efs.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.snipeit_logs.id
        iam             = "ENABLED"
      }
    }
  }

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Application Load Balancer
#------------------------------------------------------------------------------

# ALB
resource "aws_lb" "assets_alb" {
  name               = "assets-inventory-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

  enable_deletion_protection = true

  tags = merge(local.common_tags, {
    Name = "assets-inventory-alb"
  })
}

# ALB Target Group
resource "aws_lb_target_group" "snipeit_tg" {
  name        = "snipeit-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.assets_vpc.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200,302"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = local.common_tags
}

# ALB Listener (HTTP)
# Note: For production, configure HTTPS listener and change this to redirect to HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.assets_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.snipeit_tg.arn
  }
}

# Note: For HTTPS listener, you need to provide an ACM certificate ARN
# Uncomment and configure when you have a certificate, then change the HTTP listener above to redirect
# resource "aws_lb_listener" "https" {
#   load_balancer_arn = aws_lb.assets_alb.arn
#   port              = "443"
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
#   certificate_arn   = "arn:aws:acm:region:account:certificate/certificate-id"
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.snipeit_tg.arn
#   }
# }
#
# To enable HTTPS redirect, replace the HTTP listener default_action with:
#   default_action {
#     type = "redirect"
#     redirect {
#       port        = "443"
#       protocol    = "HTTPS"
#       status_code = "HTTP_301"
#     }
#   }

#------------------------------------------------------------------------------
# ECS Service
#------------------------------------------------------------------------------

resource "aws_ecs_service" "snipeit" {
  name            = "snipeit-service"
  cluster         = aws_ecs_cluster.assets_cluster.id
  task_definition = aws_ecs_task_definition.snipeit.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.ecs_subnet.id, aws_subnet.ecs_subnet_2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.snipeit_tg.arn
    container_name   = "snipeit"
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.http,
    aws_efs_mount_target.snipeit_efs_mount_1,
    aws_efs_mount_target.snipeit_efs_mount_2
  ]

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------------------

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.assets_alb.dns_name
}

output "rds_endpoint" {
  description = "Endpoint of the RDS MySQL instance"
  value       = aws_db_instance.assets_inventory_db.endpoint
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.assets_cluster.name
}

output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.snipeit_efs.id
}
