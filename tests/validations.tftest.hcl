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
# Directory service with its directory id plans.
# -----------------------------------------------------------------------------
run "directory_service_idp" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name                   = "example-validations"
    identity_provider_type = "AWS_DIRECTORY_SERVICE"
    identity_provider_details = {
      directory_id = "d-1234567890"
    }
  }

  assert {
    condition     = aws_transfer_server.default.directory_id == "d-1234567890"
    error_message = "Expected the directory id to be passed to the server."
  }
}

# -----------------------------------------------------------------------------
# Negative: SERVICE_MANAGED takes no identity provider details.
# -----------------------------------------------------------------------------
run "reject_idp_details_with_service_managed" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name = "example-validations"
    identity_provider_details = {
      function_arn = "arn:aws:lambda:eu-central-1:123456789012:function:transfer-idp"
    }
  }

  expect_failures = [var.identity_provider_details]
}

# -----------------------------------------------------------------------------
# Negative: AWS_LAMBDA needs function_arn.
# -----------------------------------------------------------------------------
run "reject_lambda_without_function" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name                   = "example-validations"
    identity_provider_type = "AWS_LAMBDA"
  }

  expect_failures = [var.identity_provider_details]
}

# -----------------------------------------------------------------------------
# Negative: API_GATEWAY needs url and invocation_role.
# -----------------------------------------------------------------------------
run "reject_api_gateway_without_invocation_role" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name                   = "example-validations"
    identity_provider_type = "API_GATEWAY"
    identity_provider_details = {
      url = "https://abc123.execute-api.eu-central-1.amazonaws.com/prod/auth"
    }
  }

  expect_failures = [var.identity_provider_details]
}

# -----------------------------------------------------------------------------
# Negative: AWS_DIRECTORY_SERVICE takes directory_id only.
# -----------------------------------------------------------------------------
run "reject_directory_service_with_lambda_details" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name                   = "example-validations"
    identity_provider_type = "AWS_DIRECTORY_SERVICE"
    identity_provider_details = {
      directory_id = "d-1234567890"
      function_arn = "arn:aws:lambda:eu-central-1:123456789012:function:transfer-idp"
    }
  }

  expect_failures = [var.identity_provider_details]
}

# -----------------------------------------------------------------------------
# Negative: one Elastic IP allocation per subnet.
# -----------------------------------------------------------------------------
run "reject_eips_not_matching_subnets" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name          = "example-validations"
    endpoint_type = "VPC"
    vpc_endpoint = {
      vpc_id                 = "vpc-0123456789abcdef0"
      subnet_ids             = ["subnet-11111111", "subnet-22222222"]
      security_group_ids     = ["sg-0123456789abcdef0"]
      address_allocation_ids = ["eipalloc-aaaabbbb"]
    }
  }

  expect_failures = [var.vpc_endpoint]
}
