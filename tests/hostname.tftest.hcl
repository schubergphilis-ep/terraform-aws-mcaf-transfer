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
# Custom hostname + Route 53 zone: tags created, zone id normalized (strips
# the optional /hostedzone/ prefix). Exercises the replace() in main.tf.
# -----------------------------------------------------------------------------
run "custom_hostname_route53" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name                   = "example-hostname"
    logging_role_arn       = "arn:aws:iam::123456789012:role/transfer-logging"
    custom_hostname        = "sftp.example.com"
    route53_hosted_zone_id = "/hostedzone/Z1D633PJN98FT9"
  }

  assert {
    condition     = aws_transfer_tag.custom_hostname[0].value == "sftp.example.com"
    error_message = "Expected custom hostname tag value sftp.example.com, got: ${aws_transfer_tag.custom_hostname[0].value}"
  }

  assert {
    condition     = aws_transfer_tag.route53_zone[0].value == "Z1D633PJN98FT9"
    error_message = "Expected zone id stripped to Z1D633PJN98FT9, got: ${aws_transfer_tag.route53_zone[0].value}"
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
    logging_role_arn       = "arn:aws:iam::123456789012:role/transfer-logging"
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
    name             = "example-bad-hostname"
    logging_role_arn = "arn:aws:iam::123456789012:role/transfer-logging"
    custom_hostname  = "-invalid.example.com"
  }

  expect_failures = [var.custom_hostname]
}
