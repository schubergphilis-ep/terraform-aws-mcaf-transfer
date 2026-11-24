provider "aws" {
  region = "eu-west-1"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  # An existing SSE-KMS bucket (bucket keys off) and its KMS key.
  bucket_arn  = "arn:aws:s3:::example-transfer-bucket"
  kms_key_arn = "arn:aws:kms:eu-west-1:111111111111:key/11111111-2222-3333-4444-555555555555"
}

# One role shared by all users. It is the upper bound: each user's session policy below limits the
# user to its own prefix.
data "aws_iam_policy_document" "user_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["transfer.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "user_role" {
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket"]
    resources = [local.bucket_arn]
  }

  statement {
    sid       = "Objects"
    actions   = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
    resources = ["${local.bucket_arn}/*"]
  }

  statement {
    sid       = "KmsViaS3"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [local.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}

module "user_role" {
  source  = "schubergphilis-ep/mcaf-role/aws"
  version = "~> 0.6.0"

  name          = "example-transfer-user"
  assume_policy = data.aws_iam_policy_document.user_assume_role.json
  create_policy = true
  description   = "Shared role of the example-transfer users, limited per user by a session policy"
  postfix       = false
  role_policy   = data.aws_iam_policy_document.user_role.json
}

# Session policy: the user's own prefix only. ${transfer:UserName} works with logical home
# directories; the HomeDirectory variables do not. The KMS statement is needed for an SSE-KMS
# bucket: without it reads fail and uploads fail when the file is closed.
data "aws_iam_policy_document" "session" {
  statement {
    sid       = "ListOwnPrefix"
    actions   = ["s3:ListBucket"]
    resources = [local.bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["$${transfer:UserName}/*"]
    }
  }

  statement {
    sid       = "OwnObjects"
    actions   = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
    resources = ["${local.bucket_arn}/$${transfer:UserName}/*"]
  }

  statement {
    sid       = "KmsOwnPrefix"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [local.kms_key_arn]

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = ["${local.bucket_arn}/$${transfer:UserName}/*"]
    }
  }
}

module "transfer_server" {
  source = "../.."

  name             = "example-transfer"
  create_log_group = true
  restricted_mode  = true

  users = {
    alice = {
      home_directory = "/example-transfer-bucket/alice"
      policy         = data.aws_iam_policy_document.session.json
      role_arn       = module.user_role.arn
      ssh_pub_keys   = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleAliceKey alice@example"]
    }

    bob = {
      home_directory = "/example-transfer-bucket/bob"
      policy         = data.aws_iam_policy_document.session.json
      role_arn       = module.user_role.arn
      ssh_pub_keys   = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleBobKey bob@example"]
    }
  }
}
