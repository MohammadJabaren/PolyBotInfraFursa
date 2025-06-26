variable "region" {
  description = "Availability zones"
  type        = string
}
variable "username" {
  description = "name of the user"
  type = string
}
variable "env" {
   description = "Deployment environment"
   type        = string
}
variable "ami_id" {
  description = "The AMI ID to use for the control panel EC2 instance"
  type        = string
}
variable "key_pair_name" {
  description = "Name of the EC2 key pair to use for SSH access"
  type        = string
}
variable "azs" {
  description = "Availability zones"
  type        = list(string)
}