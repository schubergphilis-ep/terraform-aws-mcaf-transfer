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
# Managed host keys without names: each key is named after its list index, and
# the description is not sensitive.
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
    condition     = toset(keys(aws_transfer_host_key.managed)) == toset(["0", "1"])
    error_message = "Expected host keys keyed 0 and 1, got: ${jsonencode(keys(aws_transfer_host_key.managed))}"
  }

  assert {
    condition     = aws_transfer_host_key.managed["0"].description == "primary"
    error_message = "Expected the first host key description to be primary."
  }

  assert {
    condition     = !issensitive(aws_transfer_host_key.managed["0"].description)
    error_message = "Expected the host key description not to be sensitive."
  }

  assert {
    condition     = aws_transfer_host_key.managed["1"].tags.Name == "example-hostkeys-host-key-1"
    error_message = "Expected the Name tag example-hostkeys-host-key-1, got: ${aws_transfer_host_key.managed["1"].tags.Name}"
  }
}

# -----------------------------------------------------------------------------
# Named host keys: keyed by name, so removing one leaves the others in place.
# -----------------------------------------------------------------------------
run "named_host_keys" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name             = "example-hostkeys"
    logging_role_arn = "arn:aws:iam::123456789012:role/transfer-logging"
    manage_host_keys = true
    host_keys = [
      { name = "rsa-2025", private_key = "DUMMY-PRIVATE-KEY-1" },     # checkov:skip=CKV_SECRET_6:placeholder text, not a key
      { name = "ed25519-2026", private_key = "DUMMY-PRIVATE-KEY-2" }, # checkov:skip=CKV_SECRET_6:placeholder text, not a key
    ]
  }

  assert {
    condition     = toset(keys(aws_transfer_host_key.managed)) == toset(["rsa-2025", "ed25519-2026"])
    error_message = "Expected host keys keyed by name, got: ${jsonencode(keys(aws_transfer_host_key.managed))}"
  }

  assert {
    condition     = aws_transfer_host_key.managed["ed25519-2026"].tags.Name == "example-hostkeys-host-key-ed25519-2026"
    error_message = "Expected the Name tag to carry the host key name."
  }
}

# -----------------------------------------------------------------------------
# host_keys without manage_host_keys: nothing is attached.
# -----------------------------------------------------------------------------
run "host_keys_not_managed" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name             = "example-hostkeys"
    logging_role_arn = "arn:aws:iam::123456789012:role/transfer-logging"
    host_keys = [
      { name = "rsa-2025", private_key = "DUMMY-PRIVATE-KEY-1" }, # checkov:skip=CKV_SECRET_6:placeholder text, not a key
    ]
  }

  assert {
    condition     = length(aws_transfer_host_key.managed) == 0
    error_message = "Expected no host keys when manage_host_keys is false."
  }
}

# -----------------------------------------------------------------------------
# Negative: two host keys with the same name (here a name equal to the index of
# an unnamed key).
# -----------------------------------------------------------------------------
run "reject_duplicate_host_key_names" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name             = "example-hostkeys"
    logging_role_arn = "arn:aws:iam::123456789012:role/transfer-logging"
    manage_host_keys = true
    host_keys = [
      { private_key = "DUMMY-PRIVATE-KEY-1" },             # checkov:skip=CKV_SECRET_6:placeholder text, not a key
      { name = "0", private_key = "DUMMY-PRIVATE-KEY-2" }, # checkov:skip=CKV_SECRET_6:placeholder text, not a key
    ]
  }

  expect_failures = [var.host_keys]
}
