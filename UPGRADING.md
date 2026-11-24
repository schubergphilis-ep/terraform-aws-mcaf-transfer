# Upgrading Notes

This document captures required refactoring on your part when upgrading to a module version that contains breaking changes, and what the first plan after an upgrade shows.

## Upgrading to v2.1.0

### Key Changes

No input change is needed. The module needs Terraform 1.11.0 or later and AWS provider 6.20.0 or later. The first plan after the upgrade shows:

- **SSH keys** are identified by user and a SHA-256 hash of the key body instead of their list index. Each `aws_transfer_ssh_key.default["<user>:<index>"]` is destroyed and created again as `aws_transfer_ssh_key.default["<user>:<hash>"]`, with the same key body and a new SSH key ID. During that apply a user can briefly be without the key. To move the keys instead, add a `moved` block per key to your configuration before the upgrade apply; `terraform console` prints the hash with `sha256("<key body>")`:

  ```hcl
  moved {
    from = module.transfer.aws_transfer_ssh_key.default["alice:0"]
    to   = module.transfer.aws_transfer_ssh_key.default["alice:<sha256 of alice's first key>"]
  }
  ```

  SSH keys must be known at plan time: a key that is only known after apply fails the plan.

- **Host keys** are identified by their new optional `name`, or by their list index when unnamed. The module moves `aws_transfer_host_key.managed[<index>]` to `aws_transfer_host_key.managed["<index>"]` for the first ten keys, so unnamed keys stay in place. To name an existing key, move it in your configuration as well, or it is deleted and imported again (same key material, new host key ID):

  ```hcl
  moved {
    from = module.transfer.aws_transfer_host_key.managed["0"]
    to   = module.transfer.aws_transfer_host_key.managed["rsa-2025"]
  }
  ```

  The host key `description` is no longer shown as sensitive.

- **Custom hostname tags** are set on the server's own tags. `aws_transfer_tag.custom_hostname` and `aws_transfer_tag.route53_zone` are removed from the state without being deleted, and `aws_transfer_server.default` is updated in place to add the `transfer:customHostname` and `transfer:route53HostedZoneId` tags.

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
