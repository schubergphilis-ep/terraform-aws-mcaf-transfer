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
# PATH home directories (default): no mappings, no session policy.
# -----------------------------------------------------------------------------
run "path_home_directory" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name             = "example-users"
    logging_role_arn = "arn:aws:iam::123456789012:role/transfer-logging"
    users = {
      alice = {
        home_directory = "/example-bucket/alice"
        role_arn       = "arn:aws:iam::123456789012:role/transfer-user"
        ssh_pub_keys   = []
      }
    }
  }

  assert {
    condition     = aws_transfer_user.default["alice"].home_directory_type == "PATH"
    error_message = "Expected home_directory_type PATH, got: ${aws_transfer_user.default["alice"].home_directory_type}"
  }

  assert {
    condition     = aws_transfer_user.default["alice"].home_directory == "/example-bucket/alice"
    error_message = "Expected home_directory /example-bucket/alice."
  }

  assert {
    condition     = length(aws_transfer_user.default["alice"].home_directory_mappings) == 0
    error_message = "Expected no home directory mappings with PATH home directories."
  }

  assert {
    condition     = aws_transfer_user.default["alice"].policy == null
    error_message = "Expected no session policy by default."
  }
}

# -----------------------------------------------------------------------------
# restricted_mode: one "/" mapping to the home directory, plus a session policy.
# -----------------------------------------------------------------------------
run "logical_home_directory_with_session_policy" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name             = "example-users"
    logging_role_arn = "arn:aws:iam::123456789012:role/transfer-logging"
    restricted_mode  = true
    users = {
      alice = {
        home_directory = "/example-bucket/alice"
        policy = jsonencode({
          Version = "2012-10-17"
          Statement = [
            {
              Sid       = "ListOwnPrefix"
              Effect    = "Allow"
              Action    = "s3:ListBucket"
              Resource  = "arn:aws:s3:::example-bucket"
              Condition = { StringLike = { "s3:prefix" = ["$${transfer:UserName}/*"] } }
            },
            {
              Sid      = "OwnObjects"
              Effect   = "Allow"
              Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
              Resource = "arn:aws:s3:::example-bucket/$${transfer:UserName}/*"
            },
          ]
        })
        role_arn     = "arn:aws:iam::123456789012:role/transfer-user"
        ssh_pub_keys = []
      }
    }
  }

  assert {
    condition     = aws_transfer_user.default["alice"].home_directory_type == "LOGICAL"
    error_message = "Expected home_directory_type LOGICAL, got: ${aws_transfer_user.default["alice"].home_directory_type}"
  }

  assert {
    condition     = aws_transfer_user.default["alice"].home_directory == null
    error_message = "Expected no home_directory with LOGICAL home directories."
  }

  assert {
    condition     = length(aws_transfer_user.default["alice"].home_directory_mappings) == 1 && aws_transfer_user.default["alice"].home_directory_mappings[0].entry == "/" && aws_transfer_user.default["alice"].home_directory_mappings[0].target == "/example-bucket/alice"
    error_message = "Expected a single mapping / -> /example-bucket/alice."
  }

  assert {
    condition     = jsondecode(aws_transfer_user.default["alice"].policy).Statement[1].Resource == "arn:aws:s3:::example-bucket/$${transfer:UserName}/*"
    error_message = "Expected the session policy to be set on the user."
  }
}

# -----------------------------------------------------------------------------
# restricted_mode with explicit mappings: they replace the "/" mapping.
# -----------------------------------------------------------------------------
run "logical_home_directory_mappings" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name             = "example-users"
    logging_role_arn = "arn:aws:iam::123456789012:role/transfer-logging"
    restricted_mode  = true
    users = {
      carol = {
        home_directory = "/example-bucket/carol"
        home_directory_mappings = [
          { entry = "/inbox", target = "/example-bucket/carol/inbox" },
          { entry = "/outbox", target = "/example-bucket/carol/outbox" },
        ]
        role_arn     = "arn:aws:iam::123456789012:role/transfer-user"
        ssh_pub_keys = []
      }
    }
  }

  assert {
    condition     = toset(aws_transfer_user.default["carol"].home_directory_mappings[*].entry) == toset(["/inbox", "/outbox"])
    error_message = "Expected the mappings /inbox and /outbox, got: ${jsonencode(aws_transfer_user.default["carol"].home_directory_mappings[*].entry)}"
  }
}

# -----------------------------------------------------------------------------
# Negative: user names need 3-100 characters.
# -----------------------------------------------------------------------------
run "reject_short_user_name" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name             = "example-users"
    logging_role_arn = "arn:aws:iam::123456789012:role/transfer-logging"
    users = {
      ab = {
        home_directory = "/example-bucket/ab"
        role_arn       = "arn:aws:iam::123456789012:role/transfer-user"
        ssh_pub_keys   = []
      }
    }
  }

  expect_failures = [var.users]
}

# -----------------------------------------------------------------------------
# Negative: home_directory must start with "/".
# -----------------------------------------------------------------------------
run "reject_relative_home_directory" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name             = "example-users"
    logging_role_arn = "arn:aws:iam::123456789012:role/transfer-logging"
    users = {
      alice = {
        home_directory = "example-bucket/alice"
        role_arn       = "arn:aws:iam::123456789012:role/transfer-user"
        ssh_pub_keys   = []
      }
    }
  }

  expect_failures = [var.users]
}

# -----------------------------------------------------------------------------
# Negative: a logical directory target must not end with "/".
# -----------------------------------------------------------------------------
run "reject_logical_target_with_trailing_slash" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name             = "example-users"
    logging_role_arn = "arn:aws:iam::123456789012:role/transfer-logging"
    restricted_mode  = true
    users = {
      alice = {
        home_directory = "/example-bucket/alice/"
        role_arn       = "arn:aws:iam::123456789012:role/transfer-user"
        ssh_pub_keys   = []
      }
    }
  }

  expect_failures = [var.users]
}

# -----------------------------------------------------------------------------
# Negative: "/" plus another entry overlaps, which AWS rejects.
# -----------------------------------------------------------------------------
run "reject_overlapping_mappings" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name             = "example-users"
    logging_role_arn = "arn:aws:iam::123456789012:role/transfer-logging"
    restricted_mode  = true
    users = {
      carol = {
        home_directory = "/example-bucket/carol"
        home_directory_mappings = [
          { entry = "/", target = "/example-bucket/carol" },
          { entry = "/dave", target = "/example-bucket/dave" },
        ]
        role_arn     = "arn:aws:iam::123456789012:role/transfer-user"
        ssh_pub_keys = []
      }
    }
  }

  expect_failures = [var.users]
}

# -----------------------------------------------------------------------------
# Negative: home_directory_mappings need LOGICAL home directories.
# -----------------------------------------------------------------------------
run "reject_mappings_without_restricted_mode" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name             = "example-users"
    logging_role_arn = "arn:aws:iam::123456789012:role/transfer-logging"
    users = {
      carol = {
        home_directory          = "/example-bucket/carol"
        home_directory_mappings = [{ entry = "/inbox", target = "/example-bucket/carol/inbox" }]
        role_arn                = "arn:aws:iam::123456789012:role/transfer-user"
        ssh_pub_keys            = []
      }
    }
  }

  expect_failures = [var.users]
}

# -----------------------------------------------------------------------------
# Negative: the session policy must be JSON.
# -----------------------------------------------------------------------------
run "reject_invalid_session_policy" {
  command = plan

  module {
    source = "./"
  }

  variables {
    name             = "example-users"
    logging_role_arn = "arn:aws:iam::123456789012:role/transfer-logging"
    users = {
      alice = {
        home_directory = "/example-bucket/alice"
        policy         = "not json"
        role_arn       = "arn:aws:iam::123456789012:role/transfer-user"
        ssh_pub_keys   = []
      }
    }
  }

  expect_failures = [var.users]
}
