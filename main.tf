locals {
  vpc_endpoint      = var.vpc_endpoint != null ? { create = true } : {}
  on_upload         = var.on_upload != null ? { create = true } : {}
  on_partial_upload = var.on_partial_upload != null ? { create = true } : {}
  workflow_details  = length(merge(local.on_upload, local.on_partial_upload)) > 0 ? { create = true } : {}

  # Normalize Route 53 zone ID to its raw form (strip optional "/hostedzone/" prefix).
  route53_zone_id = var.route53_hosted_zone_id == null ? null : replace(var.route53_hosted_zone_id, "/^\\/hostedzone\\//", "")

  # Custom hostname tags go on the server's own tags: separate aws_transfer_tag resources are read
  # back into the server's tags and removed again on every apply. Whether they are set depends on
  # custom_hostname only, so a zone ID that is known after apply does not fail the plan.
  hostname_tags = var.custom_hostname == null ? {} : merge(
    { "transfer:customHostname" = var.custom_hostname },
    var.route53_hosted_zone_id == null ? {} : { "transfer:route53HostedZoneId" = local.route53_zone_id },
  )

  # Users' SSH keys keyed by user name and a SHA-256 hash of the key body, so removing or
  # reordering a key leaves the other keys in place. A key listed twice for a user is imported once.
  user_ssh_keys = {
    for item in flatten([
      for user, config in var.users : [
        for ssh_key in distinct(config.ssh_pub_keys) : {
          user    = user
          ssh_key = ssh_key
        }
      ]
    ]) : "${item.user}:${sha256(item.ssh_key)}" => item
  }

  # Host keys keyed by name; an unnamed key is named after its list index. Only the private keys
  # are secret, so the names and descriptions are taken out of the sensitive host_keys input.
  host_key_list = var.manage_host_keys ? nonsensitive([
    for idx, host_key in var.host_keys : {
      description = host_key.description
      index       = idx
      name        = coalesce(host_key.name, tostring(idx))
    }
  ]) : []

  host_keys = { for host_key in local.host_key_list : host_key.name => host_key }
}

resource "aws_transfer_server" "default" {
  #checkov:skip=CKV_AWS_164: PUBLIC endpoint is required for our SFTP use case
  lifecycle {
    # prevent_destroy is intentionally NOT set: it must be a literal (cannot be
    # made conditional via a variable), so enabling it would block destroy and
    # replacement for every consumer of this module. Callers needing host-key
    # stability should pin it via manage_host_keys/host_keys or guard the server
    # in their own configuration.

    # PUBLIC → vpc_endpoint must be null
    precondition {
      condition     = (var.endpoint_type != "PUBLIC") || (var.vpc_endpoint == null)
      error_message = "endpoint_type=PUBLIC requires vpc_endpoint to be null."
    }

    # VPC → require SGs, subnets, and vpc_id
    precondition {
      condition = (
        var.endpoint_type != "VPC" ||
        (
          var.vpc_endpoint != null &&
          length(coalesce(try(var.vpc_endpoint.security_group_ids, []), [])) > 0 &&
          length(coalesce(try(var.vpc_endpoint.subnet_ids, []), [])) > 0 &&
          try(var.vpc_endpoint.vpc_id, "") != ""
        )
      )
      error_message = "endpoint_type=VPC requires vpc_endpoint.security_group_ids, vpc_endpoint.subnet_ids, and vpc_endpoint.vpc_id."
    }

    # VPC_ENDPOINT → require only vpc_endpoint_id (no SGs/subnets/vpc_id)
    precondition {
      condition = (
        var.endpoint_type != "VPC_ENDPOINT" ||
        (
          var.vpc_endpoint != null &&
          try(var.vpc_endpoint.vpc_endpoint_id, "") != "" &&
          length(coalesce(try(var.vpc_endpoint.security_group_ids, []), [])) == 0 &&
          length(coalesce(try(var.vpc_endpoint.subnet_ids, []), [])) == 0 &&
          try(var.vpc_endpoint.vpc_id, null) == null
        )
      )
      error_message = "endpoint_type=VPC_ENDPOINT requires vpc_endpoint.vpc_endpoint_id and forbids security_group_ids, subnet_ids, and vpc_id."
    }

    # sftp_authentication_methods is only valid with API_GATEWAY or AWS_LAMBDA
    precondition {
      condition = (
        var.sftp_authentication_methods == null ||
        var.identity_provider_type == "AWS_LAMBDA" ||
        var.identity_provider_type == "API_GATEWAY"
      )
      error_message = "sftp_authentication_methods is only supported for identity_provider_type of API_GATEWAY or AWS_LAMBDA."
    }

    # Security: explicitly forbid FTP even if validation is bypassed
    precondition {
      condition     = !contains(var.protocols, "FTP")
      error_message = "FTP is not allowed by this module."
    }

    # Security: forbid PASSWORD-only SFTP auth
    precondition {
      condition     = (var.sftp_authentication_methods == null) || (var.sftp_authentication_methods != "PASSWORD")
      error_message = "sftp_authentication_methods=PASSWORD is not allowed. Use PUBLIC_KEY or PUBLIC_KEY_OR_PASSWORD."
    }

    # Hardening (recommended): if FTPS is enabled on PUBLIC endpoint, require passive_ip to be set
    # to avoid ephemeral public address exposure via control connections/NAT.
    precondition {
      condition = (
        !contains(var.protocols, "FTPS") ||
        var.endpoint_type != "PUBLIC" ||
        (
          var.protocol_details != null &&
          try(var.protocol_details.passive_ip, "") != ""
        )
      )
      error_message = "When protocols include FTPS and endpoint_type=PUBLIC, protocol_details.passive_ip must be set."
    }
  }

  region = var.region

  # ── Identity provider & authentication (v5/v6) ──────────────────────────────
  identity_provider_type = var.identity_provider_type
  # NOTE: In v5+, this is a top-level arg (also valid in v6). Only for API_GATEWAY/AWS_LAMBDA.
  sftp_authentication_methods = var.sftp_authentication_methods

  # Top-level IdP detail args (supported in v5 and v6)
  function        = try(var.identity_provider_details.function_arn, null)    # AWS_LAMBDA
  invocation_role = try(var.identity_provider_details.invocation_role, null) # API_GATEWAY
  url             = try(var.identity_provider_details.url, null)             # API_GATEWAY
  directory_id    = try(var.identity_provider_details.directory_id, null)    # AWS_DIRECTORY_SERVICE

  # ── Endpoint & logging ──────────────────────────────────────────────────────
  endpoint_type               = var.endpoint_type
  logging_role                = local.logging_role_arn
  structured_log_destinations = var.create_log_group ? toset(["${aws_cloudwatch_log_group.default[0].arn}:*"]) : var.structured_log_destinations

  # ── Banners & security policy ───────────────────────────────────────────────
  pre_authentication_login_banner  = var.pre_authentication_login_banner
  post_authentication_login_banner = var.post_authentication_login_banner
  security_policy_name             = var.transfer_security_policy

  # ── Protocols ───────────────────────────────────────────────────────────────
  protocols = var.protocols

  # ── Tags (preserve original Name usage) ─────────────────────────────────────
  tags = merge(var.tags, local.hostname_tags, { Name = var.name })

  # ── Endpoint details (VPC / VPC_ENDPOINT) ───────────────────────────────────
  dynamic "endpoint_details" {
    for_each = local.vpc_endpoint
    content {
      address_allocation_ids = try(var.vpc_endpoint.address_allocation_ids, null) # VPC
      security_group_ids     = try(var.vpc_endpoint.security_group_ids, null)     # VPC
      subnet_ids             = try(var.vpc_endpoint.subnet_ids, null)             # VPC
      vpc_id                 = try(var.vpc_endpoint.vpc_id, null)                 # VPC
      vpc_endpoint_id        = try(var.vpc_endpoint.vpc_endpoint_id, null)        # VPC_ENDPOINT
    }
  }

  # ── Workflows ────────────────────────────────────────────────────────────────
  dynamic "workflow_details" {
    for_each = local.workflow_details
    content {
      dynamic "on_upload" {
        for_each = local.on_upload
        content {
          execution_role = var.on_upload.execution_role_arn
          workflow_id    = var.on_upload.workflow_id
        }
      }
      dynamic "on_partial_upload" {
        for_each = local.on_partial_upload
        content {
          execution_role = var.on_partial_upload.execution_role_arn
          workflow_id    = var.on_partial_upload.workflow_id
        }
      }
    }
  }

  # ── Protocol details (FTPS / AS2 options) ───────────────────────────────────
  dynamic "protocol_details" {
    for_each = var.protocol_details == null ? {} : { create = true }
    content {
      as2_transports              = try(var.protocol_details.as2_transports, null)
      passive_ip                  = try(var.protocol_details.passive_ip, null)
      tls_session_resumption_mode = try(var.protocol_details.tls_session_resumption_mode, null)
      # Note: sftp_authentication_methods is TOP-LEVEL (not here).
    }
  }

  # ── S3 storage options ───────────────────────────────────────────────────────
  dynamic "s3_storage_options" {
    for_each = var.s3_storage_options == null ? {} : { create = true }
    content {
      directory_listing_optimization = try(var.s3_storage_options.directory_listing_optimization, null)
    }
  }
}

# ── Optional: log group for structured logging ────────────────────────────────
# Transfer adds a resource policy for delivery.logs.amazonaws.com to the log group
# itself, as the caller, when it creates or updates the server.
resource "aws_cloudwatch_log_group" "default" {
  count = var.create_log_group ? 1 : 0

  region            = var.region
  name              = "/aws/transfer/${var.name}"
  kms_key_id        = var.kms_key_arn
  retention_in_days = var.log_retention
  skip_destroy      = var.log_group_skip_destroy
  tags              = var.tags
}

# ── Optional: logging role ────────────────────────────────────────────────────
# Used by Transfer for workflow logs and the service-managed /aws/transfer/<server-id>
# log group. Structured logging to a log group does not need it.
data "aws_caller_identity" "current" {
  count = var.create_logging_role ? 1 : 0
}

data "aws_partition" "current" {
  count = var.create_logging_role ? 1 : 0
}

data "aws_region" "current" {
  count = var.create_logging_role ? 1 : 0

  region = var.region
}

locals {
  logging_role_arn = var.create_logging_role ? module.logging_role[0].arn : var.logging_role_arn

  logging_role_scope = var.create_logging_role ? {
    account   = data.aws_caller_identity.current[0].account_id
    partition = data.aws_partition.current[0].partition
    region    = data.aws_region.current[0].region
  } : null
}

data "aws_iam_policy_document" "logging_assume_role" {
  count = var.create_logging_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["transfer.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.logging_role_scope.account]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.logging_role_scope.partition}:transfer:${local.logging_role_scope.region}:${local.logging_role_scope.account}:server/*"]
    }
  }
}

data "aws_iam_policy_document" "logging" {
  count = var.create_logging_role ? 1 : 0

  statement {
    sid = "TransferLogGroups"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["arn:${local.logging_role_scope.partition}:logs:${local.logging_role_scope.region}:${local.logging_role_scope.account}:log-group:/aws/transfer/*"]
  }
}

module "logging_role" {
  count = var.create_logging_role ? 1 : 0

  source  = "schubergphilis-ep/mcaf-role/aws"
  version = "~> 0.6.0"

  name                 = coalesce(var.logging_role_name, "TransferLogging-${var.name}")
  assume_policy        = data.aws_iam_policy_document.logging_assume_role[0].json
  create_policy        = true
  description          = var.logging_role_description
  permissions_boundary = var.logging_role_permissions_boundary
  postfix              = false
  role_policy          = data.aws_iam_policy_document.logging[0].json
  tags                 = var.tags
}

# ── VPC endpoint DNS name ─────────────────────────────────────────────────────
# An internal VPC server has no s-<id>.server.transfer.<region>.amazonaws.com DNS
# name: clients connect to the VPC endpoint.
data "aws_vpc_endpoint" "default" {
  count = var.endpoint_type == "PUBLIC" ? 0 : 1

  region = var.region
  id     = aws_transfer_server.default.endpoint_details[0].vpc_endpoint_id
}

# ── VPC_ENDPOINT is deprecated by AWS: new servers can't use it and it's absent
#    in newer regions. Emit a non-blocking warning steering callers to VPC. ─────
check "vpc_endpoint_deprecated" {
  assert {
    condition     = var.endpoint_type != "VPC_ENDPOINT"
    error_message = "endpoint_type=VPC_ENDPOINT is deprecated by AWS (new servers cannot be created with it and it is unavailable in newer regions). Migrate to endpoint_type=VPC."
  }
}

# ── Optional: explicit server host keys ───────────────────────────────────────
# Private key is supplied via the write-only argument host_key_body_wo (TF 1.11+),
# so it is never persisted to state. There is no _wo_version companion on this
# resource; rotate a key by adding a new host_keys element, then removing the old one.
resource "aws_transfer_host_key" "managed" {
  for_each = local.host_keys

  region           = var.region
  server_id        = aws_transfer_server.default.id
  host_key_body_wo = var.host_keys[each.value.index].private_key
  description      = each.value.description

  tags = merge(var.tags, { Name = "${var.name}-host-key-${each.key}" })
}

# ── Users (IAM roles provided by caller) ───────────────────────────────────────
resource "aws_transfer_user" "default" {
  for_each = var.users

  region              = var.region
  user_name           = each.key
  role                = each.value.role_arn
  policy              = each.value.policy
  server_id           = aws_transfer_server.default.id
  home_directory      = var.restricted_mode ? null : each.value.home_directory
  home_directory_type = var.restricted_mode ? "LOGICAL" : "PATH"

  # Preserve Name tagging pattern with var.name
  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })

  dynamic "home_directory_mappings" {
    for_each = var.restricted_mode ? (
      each.value.home_directory_mappings != null ? each.value.home_directory_mappings : [{ entry = "/", target = each.value.home_directory }]
    ) : []

    content {
      entry  = home_directory_mappings.value.entry
      target = home_directory_mappings.value.target
    }
  }
}

resource "aws_transfer_ssh_key" "default" {
  for_each = local.user_ssh_keys

  region    = var.region
  server_id = aws_transfer_server.default.id
  user_name = aws_transfer_user.default[each.value.user].user_name
  body      = each.value.ssh_key

  lifecycle {
    precondition {
      condition     = var.identity_provider_type == "SERVICE_MANAGED"
      error_message = "SSH public keys (ssh_pub_keys on users) are only supported when identity_provider_type=SERVICE_MANAGED. Remove ssh_pub_keys or switch the identity provider."
    }
  }
}
