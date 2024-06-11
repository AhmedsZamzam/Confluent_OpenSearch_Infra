variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)."
  type        = string
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret."
  type        = string
  sensitive   = true
}

variable "aws_key" {
  description = "AWS API Key (with Lmabda Invoke Permission)."
  type        = string
}

variable "aws_secret" {
  description = "AWS API Secret."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "The region of Confluent Cloud Network."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC Cidr to be created"
  type        = string
}


variable "prefix" {
  description = "Prefix used in all resources created"
  type        = string
}


variable "opensearch_master_username" {
  description = "The master user for the OpenSearch domain"
  type        = string
}

variable "opensearch_master_password" {
  description = "The master password for the OpenSearch domain"
  type        = string
  sensitive   = true
}

variable "availability_zones" {
  description = "List of availability zones to use for the private subnets"
  type        = list(string)
}





