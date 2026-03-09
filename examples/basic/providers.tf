provider "aws" {
  region = "us-west-2"

  default_tags {
    tags = {
      created_by = "infrahouse/terraform-aws-openclaw"
    }
  }
}