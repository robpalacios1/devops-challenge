# In this file put the variables related to the deployment
variable "environment" {
    description = "Deployment environment devel or stage"
    type = string

    validation {
        condition = contains (["devel", "stage" ], var.environment)
        error_message = "environment must be \"devel\" or \"stage\"."
    }
}

variable "aws_region" {
  description = "AWS region to deploy"
  type = string
  default = "us-east-1"
}

variable "app_name" {
    description = "Base name to build resource names"
    type = string
    default = "rdicidr"
}
