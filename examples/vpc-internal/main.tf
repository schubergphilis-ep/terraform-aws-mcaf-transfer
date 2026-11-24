provider "aws" {
  region = "eu-west-1"
}

locals {
  # An existing VPC with private subnets, the KMS key for the log group (its key policy must allow
  # logs.<region>.amazonaws.com) and the shared user role of the basic example.
  vpc_id          = "vpc-0123456789abcdef0"
  subnet_ids      = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  client_cidr     = "10.0.0.0/16"
  log_kms_key_arn = "arn:aws:kms:eu-west-1:111111111111:key/11111111-2222-3333-4444-555555555555"
  user_role_arn   = "arn:aws:iam::111111111111:role/example-transfer-user"
}

# The endpoint security group only needs SFTP ingress from the clients: security groups are
# stateful, so it has no egress rules.
resource "aws_security_group" "transfer" {
  name        = "example-transfer-internal"
  description = "SFTP to the example-transfer-internal Transfer endpoint"
  vpc_id      = local.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "sftp" {
  security_group_id = aws_security_group.transfer.id
  description       = "SFTP from the clients"
  cidr_ipv4         = local.client_cidr
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

module "transfer_server" {
  source = "../.."

  name          = "example-transfer-internal"
  endpoint_type = "VPC"

  vpc_endpoint = {
    security_group_ids = [aws_security_group.transfer.id]
    subnet_ids         = local.subnet_ids
    vpc_id             = local.vpc_id
  }

  # Structured logs in a module-owned, KMS-encrypted log group. No logging role is needed.
  create_log_group       = true
  kms_key_arn            = local.log_kms_key_arn
  log_group_skip_destroy = true

  restricted_mode = true

  users = {
    alice = {
      home_directory = "/example-transfer-bucket/alice"
      role_arn       = local.user_role_arn
      ssh_pub_keys   = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleAliceKey alice@example"]
    }
  }
}

# An internal VPC server has no DNS record for its server hostname: clients use the VPC endpoint.
output "sftp_hostname" {
  value = module.transfer_server.vpc_endpoint_dns_name
}
