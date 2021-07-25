terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
    region = "us-west-2"
}


resource "aws_vpc" "my-vpc" {
    cidr_block = "10.240.0.0/24"

    tags = {
        Name = "Kubernetes tutorial"
    }
}

resource "aws_subnet" "my-subnet" {
    vpc_id = aws_vpc.my-vpc.id
    cidr_block = "10.240.0.0/24"
    availability_zone = "us-west-2a"
}

# Security groups
resource "aws_security_group_rule" "incoming" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp,udp,icmp"
  cidr_blocks       = [aws_vpc.my-vpc.cidr_block]
  ipv6_cidr_blocks  = [aws_vpc.my-vpc.ipv6_cidr_block]
  security_group_id = "sg-123456"
}

resource "aws_security_group_rule" "outgoing" {
  type              = "egress"
  to_port           = 0
  protocol          = "-1"
  prefix_list_ids   = [aws_vpc_endpoint.my-vpc-endpoint.prefix_list_id]
  from_port         = 0
  security_group_id = "sg-123456"
}

resource "aws_vpc_endpoint" "my-vpc-endpoint" {
  vpc_id            = aws_vpc.my-vpc.id
  service_name      = "com.amazonaws.us-west-2.ec2"
  vpc_endpoint_type = "Interface"
}

# Internet gateway for the vpc - if NLB is facing externally, we need this. Internally - no need.
resource "aws_internet_gateway" "my-gateway" {
  vpc_id = aws_vpc.my-vpc.id

  tags = {
    Name = "Internet Gateway for NLB"
  }
}

resource "aws_lb" "my-nlb" {
  name               = "knlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = aws_subnet.my-subnet.*.id

  enable_deletion_protection = false

  tags = {
    Environment = "dev"
  }
}

# EC2 instances
variable "instance_conf" {
  type = map(string)
  default = {
    "ami": "ami-0dc8f589abe99f538",
    "owners": "099720109477"
    "instance-type": "t2.micro",
  }
}

variable "control-ips" {
  type = list(string)
  default = ["10.240.0.10", "10.240.0.11", "10.240.0.12"]
}

variable "worker-ips" {
  type = list(string)
  default = ["10.240.0.20", "10.240.0.21", "10.240.0.22"]
}

locals {
  ec2_conf = {
      count                  = 3
      ami                    = "${var.instance_conf["ami"]}"
      instance_type          = "${var.instance_conf["instance-type"]}"
  }
}

# access using local.ec2_conf

# ec2 network interface
resource "aws_network_interface" "control-plane" {
  subnet_id   = aws_subnet.my_subnet.id
  # private_ips = ["10.240.0.10"]

  for_each = {for ip in var.control-ips : val => ip}
  private_ips = [ each.value.ip ]

  tags = {
    Name = "control-plane-nw-${index(var.control-ips, ip)}"
  }
}

resource "aws_network_interface" "worker-node" {
  subnet_id   = aws_subnet.my_subnet.id
  # private_ips = ["10.240.0.20"]

  for_each = {for ip in var.worker-ips : val => ip}
  private_ips = [ each.value.ip ]

  tags = {
    Name = "worker-node-nw"
  }
}


output "nlb_dns" {
  value = aws_lb.my-nlb.dns_name
}