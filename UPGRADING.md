# Upgrading Notes

This document captures required refactoring on your part when upgrading to a module version that contains breaking changes, and what the first plan after an upgrade shows.

## Upgrading to v2.1.0

### Key Changes

No input change is needed. The module needs Terraform 1.11.0 or later and AWS provider 6.20.0 or later. The first plan after the upgrade shows:

- **Host keys** are identified by their new optional `name`, or by their list index when unnamed. The module moves `aws_transfer_host_key.managed[<index>]` to `aws_transfer_host_key.managed["<index>"]` for the first ten keys, so unnamed keys stay in place. To name an existing key, move it in your configuration as well, or it is deleted and imported again (same key material, new host key ID):

  ```hcl
  moved {
    from = module.transfer.aws_transfer_host_key.managed["0"]
    to   = module.transfer.aws_transfer_host_key.managed["rsa-2025"]
  }
  ```

  The host key `description` is no longer marked as sensitive: the plan shows an in-place update of each host key with the same value.

- **Custom hostname tags** are set on the server's own tags. `aws_transfer_tag.custom_hostname` and `aws_transfer_tag.route53_zone` are removed from the state without being deleted. The server keeps the `transfer:customHostname` and `transfer:route53HostedZoneId` tags: the provider reads them back into its `tags`, so the plan shows no server change.

- **VPC endpoint lookup**: for `VPC` and `VPC_ENDPOINT` servers the module reads the VPC endpoint for the `vpc_endpoint_dns_name` output, so the plan needs `ec2:DescribeVpcEndpoints`.

- **Plan-time checks** now reject inputs that AWS rejects at apply: `identity_provider_details` that do not match `identity_provider_type`, `address_allocation_ids` without one per subnet, user names outside 3-100 characters of `[A-Za-z0-9_@.-]`, a `home_directory` that does not start with `/`, a logical target that ends with `/`, and more than one or a malformed `structured_log_destinations` ARN (it must end in `:*`).

#### Variables

The following variables have been added:

- `create_log_group`, `kms_key_arn`, `log_retention` (365), `log_group_skip_destroy`: a module-owned log group for structured logging.
- `create_logging_role`, `logging_role_name`, `logging_role_description`, `logging_role_permissions_boundary`: a module-owned logging role.
- `region`
- `host_keys[*].name`
- `users[*].policy`, `users[*].home_directory_mappings`

The following variable defaults have been modified:

- `logging_role_arn` → default: `null` (previous: required). Structured logging needs no logging role.
