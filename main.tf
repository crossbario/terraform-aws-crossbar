# Copyright (c) Crossbar.io Technologies GmbH. Licensed under GPL 3.0.

terraform {
    required_version = "~>0.12"
}

# https://www.terraform.io/docs/providers/aws/index.html
provider "aws" {
    region = var.aws-region
}

resource "aws_key_pair" "crossbar_keypair" {
    key_name   = "crossbar_keypair"
    public_key = file(var.admin-pubkey)
}
