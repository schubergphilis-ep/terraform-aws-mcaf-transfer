# Mock aws provider, otherwise Terraform tries to connect to the service API.
mock_provider "aws" {
  # Mock data.aws_region: we always want to return "eu-central-1" for our tests.
  mock_data "aws_region" {
    defaults = {
      region = "eu-central-1"
    }
  }
}

# -----------------------------------------------------------------------------
# Custom hostname + Route 53 zone: set as tags on the server itself (not as
# aws_transfer_tag resources), zone id normalized (strips the optional
# /hostedzone/ prefix). The users do not get these tags.
# -----------------------------------------------------------------------------
run "custom_hostname_route53" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name                   = "example-hostname"
    tags                   = { env = "test" }
    custom_hostname        = "sftp.example.com"
    route53_hosted_zone_id = "/hostedzone/Z1D633PJN98FT9"
    users = {
      alice = {
        home_directory = "/example-bucket/alice"
        role_arn       = "arn:aws:iam::123456789012:role/transfer-user"
        ssh_pub_keys   = []
      }
    }
  }

  assert {
    condition     = aws_transfer_server.default.tags["transfer:customHostname"] == "sftp.example.com"
    error_message = "Expected server tag transfer:customHostname = sftp.example.com, got: ${jsonencode(aws_transfer_server.default.tags)}"
  }

  assert {
    condition     = aws_transfer_server.default.tags["transfer:route53HostedZoneId"] == "Z1D633PJN98FT9"
    error_message = "Expected server tag transfer:route53HostedZoneId stripped to Z1D633PJN98FT9, got: ${jsonencode(aws_transfer_server.default.tags)}"
  }

  assert {
    condition     = aws_transfer_server.default.tags.Name == "example-hostname" && aws_transfer_server.default.tags.env == "test"
    error_message = "Expected the Name and caller tags next to the hostname tags, got: ${jsonencode(aws_transfer_server.default.tags)}"
  }

  assert {
    condition     = !contains(keys(aws_transfer_user.default["alice"].tags), "transfer:customHostname")
    error_message = "Expected no hostname tags on the users."
  }
}

# -----------------------------------------------------------------------------
# Custom hostname without a Route 53 zone: only the hostname tag.
# -----------------------------------------------------------------------------
run "custom_hostname_only" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name            = "example-hostname"
    custom_hostname = "sftp.example.com"
  }

  assert {
    condition     = aws_transfer_server.default.tags["transfer:customHostname"] == "sftp.example.com"
    error_message = "Expected server tag transfer:customHostname = sftp.example.com, got: ${jsonencode(aws_transfer_server.default.tags)}"
  }

  assert {
    condition     = !contains(keys(aws_transfer_server.default.tags), "transfer:route53HostedZoneId")
    error_message = "Expected no Route 53 zone tag without route53_hosted_zone_id."
  }
}

# -----------------------------------------------------------------------------
# No custom hostname: no hostname tags.
# -----------------------------------------------------------------------------
run "no_custom_hostname" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name = "example-hostname"
  }

  assert {
    condition     = toset(keys(aws_transfer_server.default.tags)) == toset(["Name"])
    error_message = "Expected only the Name tag, got: ${jsonencode(aws_transfer_server.default.tags)}"
  }
}

# -----------------------------------------------------------------------------
# Negative: route53_hosted_zone_id set without custom_hostname is rejected by
# variable validation.
# -----------------------------------------------------------------------------
run "reject_route53_without_hostname" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name                   = "example-bad-zone"
    route53_hosted_zone_id = "Z1D633PJN98FT9"
    # custom_hostname intentionally omitted
  }

  expect_failures = [var.route53_hosted_zone_id]
}

# -----------------------------------------------------------------------------
# Negative: a malformed custom_hostname (leading hyphen) is rejected by the
# DNS hostname validation.
# -----------------------------------------------------------------------------
run "reject_invalid_custom_hostname" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name            = "example-bad-hostname"
    custom_hostname = "-invalid.example.com"
  }

  expect_failures = [var.custom_hostname]
}
