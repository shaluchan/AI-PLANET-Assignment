provider "aws" {
  region = var.aws_region
}

# Networking (VPC)
resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "prefect-ecs" }
}

data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "prefect-ecs" }
}

# Public subnets
resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "prefect-ecs" }
}

# Private subnets
resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet("10.0.0.0/16", 8, count.index + 3)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "prefect-ecs" }
}

# NAT Gateway (1 for all private subnets)
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "prefect-ecs" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "prefect-ecs" }
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route { 
    cidr_block = "0.0.0.0/0" 
    gateway_id = aws_internet_gateway.igw.id
    }
  tags = { Name = "prefect-ecs" }
}

resource "aws_route_table_association" "public_assoc" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  route { 
    cidr_block = "0.0.0.0/0" 
    nat_gateway_id = aws_nat_gateway.nat.id 
    }
  tags = { Name = "prefect-ecs" }
}

resource "aws_route_table_association" "private_assoc" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ECS Cluster & Service Discovery
resource "aws_ecs_cluster" "cluster" {
  name = "prefect-cluster"
  tags = { Name = "prefect-ecs" }
}

resource "aws_service_discovery_private_dns_namespace" "ns" {
  name        = "default.prefect.local"
  description = "Private namespace for ECS"
  vpc         = aws_vpc.this.id
  tags        = { Name = "prefect-ecs" }
}

# IAM Roles
data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { 
        type = "Service" 
        identifiers = ["ecs-tasks.amazonaws.com"] 
        }
  }
}

resource "aws_iam_role" "task_exec" {
  name               = "prefect-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
  tags               = { Name = "prefect-ecs" }
}

resource "aws_iam_role_policy_attachment" "ecs_exec" {
  role       = aws_iam_role.task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "secrets_read" {
  name   = "prefect-secrets-read"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["secretsmanager:GetSecretValue"],
      Resource =[
            data.aws_secretsmanager_secret.prefect_api_key.arn,
            "${data.aws_secretsmanager_secret.prefect_api_key.arn}*"
        ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_read_attach" {
  role       = aws_iam_role.task_exec.name
  policy_arn = aws_iam_policy.secrets_read.arn
}

# Secrets Manager
data "aws_secretsmanager_secret" "prefect_api_key" {
  name = "prefect_api_key"
  tags = { Name = "prefect-ecs" }
}

data "aws_secretsmanager_secret_version" "prefect_api_key_v" {
  secret_id = data.aws_secretsmanager_secret.prefect_api_key.id
}

# ECS Task & Service

resource "aws_cloudwatch_log_group" "prefect_worker" {
  name              = "/ecs/dev-worker"
  retention_in_days = 7

  tags = {
    Name = "prefect_ecs"
  }
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "prefect-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_exec.arn

  container_definitions = jsonencode([
    {
      name      = "dev-worker"
      image     = "prefecthq/prefect:2-latest"
      essential = true
      command   = [
          "prefect", "worker", "start", 
          "--pool", "ecs-work-pool", 
          "--name", "dev-worker"
          ]
      environment = [
  {
    name  = "PREFECT_API_URL"
    value = "https://api.prefect.cloud/api/accounts/${var.prefect_account_id}/workspaces/${var.prefect_workspace_id}"
  }
]

      secrets = [
        {
          name      = "PREFECT_API_KEY",
          valueFrom = data.aws_secretsmanager_secret_version.prefect_api_key_v.arn
        }
      ]

      logConfiguration = {
      logDriver = "awslogs",
      options = {
        awslogs-group         = aws_cloudwatch_log_group.prefect_worker.name,
        awslogs-region        = var.aws_region,
        awslogs-stream-prefix = "ecs"
      }
    }
    }
  ])
}

resource "aws_service_discovery_service" "worker" {
  name = "prefect-worker"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.ns.id
    dns_records { 
        type = "A"
        ttl = 10
        }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config { 

   }
  tags = { Name = "prefect-ecs" }
}

resource "aws_ecs_service" "worker_svc" {
  name            = "prefect-worker-svc"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.prefect_worker.id]
    subnets          = aws_subnet.private[*].id
  }

  service_registries {
    registry_arn = aws_service_discovery_service.worker.arn
  }

  tags = { Name = "prefect-ecs" }
}

resource "aws_security_group" "prefect_worker" {
  name_prefix = "prefect-worker-"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "prefect-ecs"
  }
}