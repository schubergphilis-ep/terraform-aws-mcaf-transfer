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
# No logging inputs: no log group, no logging role, no structured logging.
# -----------------------------------------------------------------------------
run "no_logging" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name = "example-logging"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.default) == 0
    error_message = "Expected no log group by default."
  }

  assert {
    condition     = aws_transfer_server.default.logging_role == null
    error_message = "Expected no logging role by default."
  }

  assert {
    condition     = aws_transfer_server.default.structured_log_destinations == null
    error_message = "Expected no structured log destinations by default."
  }
}

# -----------------------------------------------------------------------------
# Module-owned log group: KMS, 365 days, structured logs sent to it, no role.
# -----------------------------------------------------------------------------
run "create_log_group" {
  command = plan

  module {
    source = "./"
  }

  override_resource {
    target          = aws_cloudwatch_log_group.default
    override_during = plan
    values = {
      arn = "arn:aws:logs:eu-central-1:123456789012:log-group:/aws/transfer/example-logging"
    }
  }

  variables {
    name             = "example-logging"
    create_log_group = true
    kms_key_arn      = "arn:aws:kms:eu-central-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = aws_cloudwatch_log_group.default[0].name == "/aws/transfer/example-logging"
    error_message = "Expected the log group /aws/transfer/example-logging, got: ${aws_cloudwatch_log_group.default[0].name}"
  }

  assert {
    condition     = aws_cloudwatch_log_group.default[0].kms_key_id == "arn:aws:kms:eu-central-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "Expected the log group to use kms_key_arn."
  }

  assert {
    condition     = aws_cloudwatch_log_group.default[0].retention_in_days == 365
    error_message = "Expected a retention of 365 days, got: ${aws_cloudwatch_log_group.default[0].retention_in_days}"
  }

  assert {
    condition     = aws_cloudwatch_log_group.default[0].skip_destroy == false
    error_message = "Expected skip_destroy to default to false."
  }

  assert {
    condition     = aws_transfer_server.default.structured_log_destinations == toset(["arn:aws:logs:eu-central-1:123456789012:log-group:/aws/transfer/example-logging:*"])
    error_message = "Expected the server to log to the module's log group, got: ${jsonencode(aws_transfer_server.default.structured_log_destinations)}"
  }

  assert {
    condition     = aws_transfer_server.default.logging_role == null
    error_message = "Expected no logging role for structured logging."
  }
}

# -----------------------------------------------------------------------------
# Log group options: retention and skip_destroy.
# -----------------------------------------------------------------------------
run "log_group_options" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name                   = "example-logging"
    create_log_group       = true
    log_retention          = 731
    log_group_skip_destroy = true
  }

  assert {
    condition     = aws_cloudwatch_log_group.default[0].retention_in_days == 731
    error_message = "Expected a retention of 731 days, got: ${aws_cloudwatch_log_group.default[0].retention_in_days}"
  }

  assert {
    condition     = aws_cloudwatch_log_group.default[0].skip_destroy == true
    error_message = "Expected skip_destroy to be true."
  }
}

# -----------------------------------------------------------------------------
# External structured log destination and logging role are passed through.
# -----------------------------------------------------------------------------
run "external_destination_and_role" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name                        = "example-logging"
    logging_role_arn            = "arn:aws:iam::123456789012:role/transfer-logging"
    structured_log_destinations = ["arn:aws:logs:eu-central-1:123456789012:log-group:/transfer/example:*"]
  }

  assert {
    condition     = aws_transfer_server.default.structured_log_destinations == toset(["arn:aws:logs:eu-central-1:123456789012:log-group:/transfer/example:*"])
    error_message = "Expected the external log destination, got: ${jsonencode(aws_transfer_server.default.structured_log_destinations)}"
  }

  assert {
    condition     = aws_transfer_server.default.logging_role == "arn:aws:iam::123456789012:role/transfer-logging"
    error_message = "Expected the external logging role."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.default) == 0
    error_message = "Expected no module-owned log group."
  }
}

# -----------------------------------------------------------------------------
# Negative: create_log_group and structured_log_destinations together.
# -----------------------------------------------------------------------------
run "reject_log_group_and_destinations" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name                        = "example-logging"
    create_log_group            = true
    structured_log_destinations = ["arn:aws:logs:eu-central-1:123456789012:log-group:/transfer/example:*"]
  }

  expect_failures = [var.create_log_group]
}

# -----------------------------------------------------------------------------
# Negative: a structured log destination without the ":*" suffix.
# -----------------------------------------------------------------------------
run "reject_destination_without_suffix" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name                        = "example-logging"
    structured_log_destinations = ["arn:aws:logs:eu-central-1:123456789012:log-group:/transfer/example"]
  }

  expect_failures = [var.structured_log_destinations]
}

# -----------------------------------------------------------------------------
# Negative: more than one structured log destination.
# -----------------------------------------------------------------------------
run "reject_two_destinations" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name = "example-logging"
    structured_log_destinations = [
      "arn:aws:logs:eu-central-1:123456789012:log-group:/transfer/one:*",
      "arn:aws:logs:eu-central-1:123456789012:log-group:/transfer/two:*",
    ]
  }

  expect_failures = [var.structured_log_destinations]
}
