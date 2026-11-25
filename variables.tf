variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance1_name" {
  description = "Value of the Name tag for the first web server (public subnet, AZ 1)"
  type        = string
  default     = "web-server-1"
}

variable "instance2_name" {
  description = "Value of the Name tag for the second web server (public subnet, AZ 2)"
  type        = string
  default     = "web-server-2"
}

variable "instance_type" {
  description = "EC2 instance type for the web servers"
  type        = string
  default     = "t3.micro"
}
