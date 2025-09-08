output "ecs_cluster_name" {
  value       = aws_ecs_cluster.cluster.name
  description = "ECS cluster name"
}

output "ecs_cluster_arn" {
  value       = aws_ecs_cluster.cluster.arn
  description = "ECS cluster ARN"
}