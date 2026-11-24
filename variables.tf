# ──────────────────────────────────────────────────────────────────────────────
# Core identifiers
# ──────────────────────────────────────────────────────────────────────────────
variable "name" {
  type        = string
  description = "A unique name for this transfer server instance. Used as the Name tag in the AWS Transfer Family console."

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{0,62}$", var.name))
    error_message = "name must start with a letter and contain only letters, numbers, and hyphens, with a maximum length of 63 characters."
  }
}

variable "region" {
  type        = string
  default     = null
  description = "The AWS region where resources will be created; if omitted the default provider region is used"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to assign to resources. Prefer provider default_tags at root."
}

# ──────────────────────────────────────────────────────────────────────────────
# Endpoint configuration
# ──────────────────────────────────────────────────────────────────────────────
variable "endpoint_type" {
  description = "Endpoint type: PUBLIC | VPC | VPC_ENDPOINT"
  type        = string
  default     = "PUBLIC"
  validation {
    condition     = contains(["PUBLIC", "VPC", "VPC_ENDPOINT"], var.endpoint_type)
    error_message = "Allowed values: PUBLIC, VPC, or VPC_ENDPOINT."
  }
}

variable "vpc_endpoint" {
  type = object({
    address_allocation_ids = optional(list(string))
    security_group_ids     = optional(list(string))
    subnet_ids             = optional(list(string))
    vpc_endpoint_id        = optional(string)
    vpc_id                 = optional(string)
  })
  default     = null
  description = "Endpoint details depending on endpoint_type. For VPC, set vpc_id, subnet_ids, security_group_ids[, address_allocation_ids]. For VPC_ENDPOINT, set vpc_endpoint_id."

  validation {
    condition = var.vpc_endpoint == null ? true : (
      var.vpc_endpoint.address_allocation_ids == null ? true : (
        length(var.vpc_endpoint.address_allocation_ids) == 0 ||
        length(var.vpc_endpoint.address_allocation_ids) == (var.vpc_endpoint.subnet_ids == null ? 0 : length(var.vpc_endpoint.subnet_ids))
      )
    )
    error_message = "vpc_endpoint.address_allocation_ids needs one Elastic IP allocation per subnet in vpc_endpoint.subnet_ids."
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Protocols & security policy (FTP forbidden)
# ──────────────────────────────────────────────────────────────────────────────
variable "protocols" {
  description = "Enabled protocols (FTP is forbidden): any of SFTP, FTPS, AS2. Note: AS2 only enables the protocol on the server; agreements, connectors, profiles, and certificates are managed outside this module."
  type        = list(string)
  default     = ["SFTP"]
  validation {
    condition     = length(var.protocols) > 0 && alltrue([for p in var.protocols : contains(["SFTP", "FTPS", "AS2"], p)])
    error_message = "Protocols must be a non-empty list with elements in {SFTP, FTPS, AS2}. FTP is not allowed."
  }
}

variable "transfer_security_policy" {
  type = string
  # Choose a provider-supported policy your org approves.
  # Examples: TransferSecurityPolicy-2025-03, TransferSecurityPolicy-2024-01,
  # TransferSecurityPolicy-FIPS-2025-03, TransferSecurityPolicy-Restricted-2024-06
  default     = "TransferSecurityPolicy-2025-03"
  description = "Explicit AWS Transfer security policy name. Pin a current, provider-supported value to avoid drift and satisfy CKV_AWS_380."

  # Basic + hardened format check: require canonical prefix and a YYYY-MM suffix for year >= 2023.
  # (Allows FIPS/Restricted/PQ variants too.)
  validation {
    condition     = can(regex("^TransferSecurityPolicy(?:-[A-Za-z0-9]+)?-20(2[3-9]|[3-9][0-9])-(0[1-9]|1[0-2])$", var.transfer_security_policy))
    error_message = "transfer_security_policy must look like TransferSecurityPolicy[-Variant]-YYYY-MM with year >= 2023 (e.g., TransferSecurityPolicy-2025-03, TransferSecurityPolicy-FIPS-2025-03, or TransferSecurityPolicy-AS2Restricted-2025-07)."
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Identity provider
# ──────────────────────────────────────────────────────────────────────────────
variable "identity_provider_type" {
  type        = string
  default     = "SERVICE_MANAGED"
  description = "SERVICE_MANAGED | AWS_LAMBDA | API_GATEWAY | AWS_DIRECTORY_SERVICE"
  validation {
    condition     = contains(["SERVICE_MANAGED", "AWS_LAMBDA", "API_GATEWAY", "AWS_DIRECTORY_SERVICE"], var.identity_provider_type)
    error_message = "identity_provider_type must be one of SERVICE_MANAGED, AWS_LAMBDA, API_GATEWAY, AWS_DIRECTORY_SERVICE."
  }
}

variable "identity_provider_details" {
  type = object({
    function_arn    = optional(string) # For AWS_LAMBDA
    invocation_role = optional(string) # For API_GATEWAY
    url             = optional(string) # For API_GATEWAY
    directory_id    = optional(string) # For AWS_DIRECTORY_SERVICE
  })
  default     = null
  description = "Identity provider details; fields depend on identity_provider_type: function_arn for AWS_LAMBDA, url and invocation_role for API_GATEWAY, directory_id for AWS_DIRECTORY_SERVICE, none for SERVICE_MANAGED."

  validation {
    condition = toset(var.identity_provider_details == null ? [] : [for field, value in var.identity_provider_details : field if value != null]) == lookup({
      SERVICE_MANAGED       = toset([])
      AWS_LAMBDA            = toset(["function_arn"])
      API_GATEWAY           = toset(["invocation_role", "url"])
      AWS_DIRECTORY_SERVICE = toset(["directory_id"])
    }, var.identity_provider_type, toset([]))
    error_message = "identity_provider_details must match identity_provider_type: function_arn for AWS_LAMBDA, url and invocation_role for API_GATEWAY, directory_id for AWS_DIRECTORY_SERVICE, and none for SERVICE_MANAGED."
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Protocol details
# ──────────────────────────────────────────────────────────────────────────────
variable "protocol_details" {
  type = object({
    as2_transports              = optional(list(string)) # AS2 transport, e.g. ["HTTP"]
    passive_ip                  = optional(string)       # FTPS passive-mode public IP
    tls_session_resumption_mode = optional(string)       # ENABLED | DISABLED (FTPS)
  })
  default     = null
  description = "Advanced protocol details for FTPS and AS2. Note: FTP is not supported by this module."
}

# ──────────────────────────────────────────────────────────────────────────────
# SFTP authentication (top-level; not part of protocol_details)
# ──────────────────────────────────────────────────────────────────────────────
variable "sftp_authentication_methods" {
  type        = string
  default     = null
  description = "Optional SFTP authentication mode. PASSWORD-only is forbidden. Valid only with identity_provider_type of API_GATEWAY or AWS_LAMBDA."

  validation {
    condition = try(
      var.sftp_authentication_methods == null ||
      contains(
        [
          # "PASSWORD",                # explicitly forbidden
          "PUBLIC_KEY",
          "PUBLIC_KEY_OR_PASSWORD",
        ],
        var.sftp_authentication_methods
      ),
      true
    )
    error_message = "sftp_authentication_methods must be one of PUBLIC_KEY, PUBLIC_KEY_OR_PASSWORD, or null. PASSWORD-only is not allowed."
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Banners
# ──────────────────────────────────────────────────────────────────────────────
variable "pre_authentication_login_banner" {
  type        = string
  default     = null
  description = "Banner shown before authentication."
}

variable "post_authentication_login_banner" {
  type        = string
  default     = null
  description = "Banner shown after authentication."
}

# ──────────────────────────────────────────────────────────────────────────────
# Logging (IAM decoupled)
# ──────────────────────────────────────────────────────────────────────────────
variable "logging_role_arn" {
  type        = string
  default     = null
  description = "IAM role ARN assumed by Transfer for CloudWatch logging (created outside this module). Needed for workflow logs and for the service-managed /aws/transfer/<server-id> log group; structured logging needs no role."
}

variable "create_logging_role" {
  type        = bool
  default     = false
  description = "Create an IAM role that Transfer uses to write workflow logs and the service-managed /aws/transfer/<server-id> log group. Conflicts with logging_role_arn."

  validation {
    condition     = !var.create_logging_role || var.logging_role_arn == null
    error_message = "Set either create_logging_role or logging_role_arn, not both."
  }

  validation {
    condition     = !var.create_logging_role || length(coalesce(var.logging_role_name, "TransferLogging-${var.name}")) <= 64
    error_message = "The logging role name is longer than 64 characters: set a shorter logging_role_name."
  }
}

variable "logging_role_description" {
  type        = string
  default     = null
  description = "Description of the IAM role created with create_logging_role"
}

variable "logging_role_name" {
  type        = string
  default     = null
  description = "Name of the IAM role created with create_logging_role. Defaults to TransferLogging-<name>"
}

variable "logging_role_permissions_boundary" {
  type        = string
  default     = null
  description = "ARN of the permissions boundary to set on the IAM role created with create_logging_role"
}

variable "structured_log_destinations" {
  type        = set(string)
  default     = null
  description = "Set of CloudWatch Logs log-group ARNs for structured (JSON) logging, in the form arn:<partition>:logs:<region>:<account>:log-group:<name>:*. At most one. Leave null to use unstructured logging, or use create_log_group."

  validation {
    condition = var.structured_log_destinations == null ? true : (
      length(var.structured_log_destinations) <= 1 &&
      alltrue([for arn in var.structured_log_destinations : can(regex("^arn:[^:]+:logs:[^:]+:[0-9]{12}:log-group:[^:]+:\\*$", arn))])
    )
    error_message = "structured_log_destinations takes at most one log group ARN, ending in \":*\" (arn:<partition>:logs:<region>:<account>:log-group:<name>:*)."
  }
}

variable "create_log_group" {
  type        = bool
  default     = false
  description = "Create the CloudWatch log group /aws/transfer/<name> and send the server's structured (JSON) logs to it. Conflicts with structured_log_destinations."

  validation {
    condition     = !var.create_log_group || (var.structured_log_destinations == null ? true : length(var.structured_log_destinations) == 0)
    error_message = "Set either create_log_group or structured_log_destinations, not both."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "The ARN of the KMS key used to encrypt the CloudWatch log group created with create_log_group"
}

variable "log_retention" {
  type        = number
  default     = 365
  description = "Number of days to retain log events in the log group created with create_log_group"
}

variable "log_group_skip_destroy" {
  type        = bool
  default     = false
  description = "Keep the log group created with create_log_group, and the log events in it, when the module is destroyed: Terraform only removes it from the state"
}

# ──────────────────────────────────────────────────────────────────────────────
# S3 storage options
# ──────────────────────────────────────────────────────────────────────────────
variable "s3_storage_options" {
  type = object({
    directory_listing_optimization = optional(string) # ENABLED | DISABLED
  })
  default     = null
  description = "S3 storage options. Set directory_listing_optimization to ENABLED to speed up directory listings on S3-backed servers."
}

# ──────────────────────────────────────────────────────────────────────────────
# Users (IAM decoupled)
# ──────────────────────────────────────────────────────────────────────────────
variable "restricted_mode" {
  type        = bool
  default     = false
  description = "Lock users to logical home directories (LOGICAL) with mappings."
}

variable "users" {
  type = map(object({
    home_directory = string
    home_directory_mappings = optional(list(object({
      entry  = string
      target = string
    })))
    policy       = optional(string)
    role_arn     = string # External IAM role (created in your IAM module)
    ssh_pub_keys = list(string)
  }))
  default     = {}
  description = "Transfer users keyed by user name. home_directory is the PATH home directory, or with restricted_mode the target of the \"/\" mapping. home_directory_mappings (restricted_mode only) replaces that single mapping. policy is an optional session policy (JSON). Each SSH key is identified by its user and a SHA-256 hash of the key body, so the keys must be known at plan time."

  validation {
    condition     = alltrue([for name in keys(var.users) : can(regex("^[\\w][\\w@.-]{2,99}$", name))])
    error_message = "User names must be 3-100 characters of letters, digits, underscores, hyphens, periods and at signs, and must not start with a hyphen, period or at sign."
  }

  validation {
    condition = alltrue([
      for user in values(var.users) : user.home_directory == "" || (can(regex("^/", user.home_directory)) && length(user.home_directory) <= 1024)
    ])
    error_message = "home_directory must be an absolute path: start with \"/\", at most 1024 characters."
  }

  validation {
    condition = !var.restricted_mode || alltrue([
      for user in values(var.users) : user.home_directory_mappings != null || can(regex("^/.*[^/]$", user.home_directory))
    ])
    error_message = "With restricted_mode, home_directory is a logical directory target: it must start with \"/\" and must not end with \"/\"."
  }

  validation {
    condition     = var.restricted_mode || alltrue([for user in values(var.users) : user.home_directory_mappings == null])
    error_message = "home_directory_mappings needs restricted_mode = true (LOGICAL home directories)."
  }

  validation {
    condition = alltrue(flatten([
      for user in values(var.users) : [
        for mapping in(user.home_directory_mappings == null ? [] : user.home_directory_mappings) : can(regex("^/", mapping.entry)) && can(regex("^/.*[^/]$", mapping.target))
      ]
    ]))
    error_message = "Each home_directory_mappings entry must start with \"/\", and each target must start with \"/\" and must not end with \"/\"."
  }

  validation {
    condition = alltrue([
      for user in values(var.users) : user.home_directory_mappings == null ? true : (
        length(user.home_directory_mappings) > 0 &&
        length(distinct(user.home_directory_mappings[*].entry)) == length(user.home_directory_mappings) &&
        (length(user.home_directory_mappings) == 1 || !contains(user.home_directory_mappings[*].entry, "/"))
      )
    ])
    error_message = "home_directory_mappings must not overlap: entries must be unique, and an entry \"/\" must be the only mapping of its user."
  }

  validation {
    condition     = alltrue([for user in values(var.users) : user.policy == null || can(jsondecode(user.policy))])
    error_message = "A user's policy must be a JSON session policy document."
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Workflows (IAM decoupled)
# ──────────────────────────────────────────────────────────────────────────────
variable "on_upload" {
  type = object({
    execution_role_arn = string
    workflow_id        = string
  })
  default     = null
  description = "Optional workflow to execute after a file is uploaded."
}

variable "on_partial_upload" {
  type = object({
    execution_role_arn = string
    workflow_id        = string
  })
  default     = null
  description = "Optional workflow to execute after a file is partially uploaded."
}

# ──────────────────────────────────────────────────────────────────────────────
# Custom hostname (console display / optional Route 53 integration)
# ──────────────────────────────────────────────────────────────────────────────

variable "custom_hostname" {
  type        = string
  default     = null
  description = "Optional custom DNS name to display in the AWS Transfer console Hostname column."

  # DNS hostname validation: dot-separated labels, each 1-63 chars, starting and
  # ending alphanumeric (no leading/trailing dots or hyphens).
  validation {
    condition = (
      var.custom_hostname == null ||
      can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$", var.custom_hostname))
    )
    error_message = "custom_hostname must be a valid DNS name: dot-separated labels of letters, numbers, and hyphens, each starting and ending with an alphanumeric character."
  }
}

variable "route53_hosted_zone_id" {
  type        = string
  default     = null
  description = "Optional Route 53 hosted zone ID for the custom hostname."

  validation {
    condition = (
      # OK if unset
      var.route53_hosted_zone_id == null
      ||
      (
        # Must be valid ID format
        can(regex("^(/hostedzone/)?Z[A-Z0-9]+$", var.route53_hosted_zone_id))
        # And a hostname MUST be set if a zone is set
        && var.custom_hostname != null
      )
    )
    error_message = "If route53_hosted_zone_id is set, it must be a valid Route 53 zone ID and custom_hostname must also be provided."
  }
}


# ──────────────────────────────────────────────────────────────────────────────
# Host key safeguard (manage host identity via write-only API)
# ──────────────────────────────────────────────────────────────────────────────
# tflint-ignore: terraform_typed_variables,terraform_unused_declarations
variable "manage_host_keys" {
  type        = bool
  default     = false
  description = "If true, attach/import host key(s) to the server using write-only private keys."
}

# tflint-ignore: terraform_typed_variables,terraform_unused_declarations
variable "host_keys" {
  type = list(object({
    name        = optional(string) # Stable key of the host key resource; defaults to the list index
    private_key = string           # Sensitive; inject from CI/env
    description = optional(string)
  }))
  default     = []
  sensitive   = true
  description = "List of host keys to attach. Each key is identified by its name (the list index when unset), so removing or reordering a named key leaves the others in place. Private keys are passed via the write-only host_key_body_wo argument (TF 1.11+) and are never stored in state."

  validation {
    condition     = length(distinct([for idx, host_key in var.host_keys : coalesce(host_key.name, tostring(idx))])) == length(var.host_keys)
    error_message = "host_keys names must be unique. An unnamed key is named after its list index."
  }
}
