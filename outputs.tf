output "endpoint" {
  value       = aws_transfer_server.default.endpoint
  description = "Endpoint hostname of the server. An internal VPC server has no DNS record for it: use vpc_endpoint_dns_name."
}

output "server_id" {
  value       = aws_transfer_server.default.id
  description = "Server ID (stable identifier; must not change)."
}

output "server_arn" {
  value       = aws_transfer_server.default.arn
  description = "ARN of the transfer server."
}

output "user_arns" {
  value       = { for name, u in aws_transfer_user.default : name => u.arn }
  description = "ARNs of the transfer users."
}

output "host_key_ids" {
  value       = [for host_key in local.host_key_list : aws_transfer_host_key.managed[host_key.name].host_key_id]
  description = "IDs of managed host keys attached to this server."
}

output "host_key_fingerprint" {
  value       = aws_transfer_server.default.host_key_fingerprint
  description = "Fingerprint of the server's host key."
}

output "host_key_fingerprints" {
  value       = { for name, host_key in aws_transfer_host_key.managed : name => host_key.host_key_fingerprint }
  description = "Fingerprints of the managed host keys, by host key name."
}

output "log_group_arn" {
  value       = try(aws_cloudwatch_log_group.default[0].arn, null)
  description = "ARN of the log group created with create_log_group."
}

output "log_group_name" {
  value       = try(aws_cloudwatch_log_group.default[0].name, null)
  description = "Name of the log group created with create_log_group."
}

output "logging_role_arn" {
  value       = local.logging_role_arn
  description = "ARN of the logging role of the server: the role created with create_logging_role, or logging_role_arn."
}

output "ssh_key_ids" {
  value       = { for key, ssh_key in aws_transfer_ssh_key.default : key => ssh_key.ssh_key_id }
  description = "IDs of the imported SSH public keys, by \"<user>:<index in ssh_pub_keys>\"."
}

output "vpc_endpoint_dns_name" {
  value       = try(data.aws_vpc_endpoint.default[0].dns_entry[0].dns_name, null)
  description = "Regional DNS name of the server's VPC endpoint (VPC and VPC_ENDPOINT endpoint types)."
}

output "vpc_endpoint_id" {
  value       = try(aws_transfer_server.default.endpoint_details[0].vpc_endpoint_id, null)
  description = "ID of the server's VPC endpoint (VPC and VPC_ENDPOINT endpoint types)."
}
