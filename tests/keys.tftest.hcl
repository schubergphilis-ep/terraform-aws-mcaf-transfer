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
# Managed host keys: count is derived from a sensitive variable, so it must be
# de-sensitized. Exercises manage_host_keys=true + host_keys.
# -----------------------------------------------------------------------------
run "manage_host_keys" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name             = "example-hostkeys"
    logging_role_arn = "arn:aws:iam::123456789012:role/transfer-logging"
    manage_host_keys = true
    host_keys = [
      { private_key = "DUMMY-PRIVATE-KEY-1", description = "primary" }, # checkov:skip=CKV_SECRET_6:placeholder text, not a key
      { private_key = "DUMMY-PRIVATE-KEY-2" },                          # checkov:skip=CKV_SECRET_6:placeholder text, not a key
    ]
  }

  assert {
    condition     = length(aws_transfer_host_key.managed) == 2
    error_message = "Expected 2 managed host keys, got: ${length(aws_transfer_host_key.managed)}"
  }
}
