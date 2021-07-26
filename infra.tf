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
## WHAT THIS AIMS TO ACHIEVE:
## 1. Set up our own Virtual Private Cloud (VPC) -> Subnet for our Kubernetes exercises
## 2. Set up firewall rules 
## 3. Set up 6 Compute instances - 3 instances for the control nodes and 3 instances for the worker nodes

# Set up VPC
resource "aws_vpc" "my-vpc" {
  cidr_block = "10.240.0.0/24"

  tags = {
    Name = "Kubernetes tutorial"
  }
}

# Subnet for the above VPC
resource "aws_subnet" "my-subnet" {
  vpc_id            = aws_vpc.my-vpc.id
  cidr_block        = "10.240.0.0/24"
  availability_zone = "us-west-2a"
}

# Traffic rules for our VPC. Only allow SSH, HTTP and ICMP (from external sources)
resource "aws_security_group" "vpc-traffic-rules" {
  description = "Traffic rules for VPC"
  vpc_id      = aws_vpc.my-vpc.id

  # Allow all protocols and ports to be run internally within the subnet
  ingress = [
    {
      description      = "tcp, icmp, udp"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = null
      ipv6_cidr_blocks = null
      prefix_list_ids  = null
      security_groups  = null
      self             = null
    }
  ]

  # Allow only SSH, HTTPS and ICMP from external network calls
  egress = [
    {
      description      = "SSH"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      cidr_blocks      = null
      ipv6_cidr_blocks = null
      prefix_list_ids  = null
      security_groups  = null
      self             = null
    },
    {
      description      = "HTTPS"
      from_port        = 443
      to_port          = 443
      protocol         = "tcp"
      cidr_blocks      = null
      ipv6_cidr_blocks = null
      prefix_list_ids  = null
      security_groups  = null
      self             = null
    },
    {
      description      = "ICMP"
      from_port        = 0
      to_port          = 1
      protocol         = "icmp"
      cidr_blocks      = null
      ipv6_cidr_blocks = null
      prefix_list_ids  = null
      security_groups  = null
      self             = null
    }
  ]
}

# Internet gateway for the vpc - if NLB is facing externally, we need this. Internally - no need.
resource "aws_internet_gateway" "my-gateway" {
  vpc_id = aws_vpc.my-vpc.id

  tags = {
    Name = "Internet Gateway for NLB"
  }
}

# Network load balancer
resource "aws_lb" "my-nlb" {
  name               = "knlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = aws_subnet.my-subnet.*.id

  # avoid keeping this as true
  enable_deletion_protection = false

  tags = {
    Environment = "dev"
  }
}

# EC2 config values
variable "instance_conf" {
  type = map(string)
  default = {
    "ami" : "ami-0dc8f589abe99f538",
    "owners" : "099720109477"
    "instance-type" : "t2.micro",
  }
}

# Kubernetes control node IPs within our subnet
variable "control-ips" {
  type    = list(string)
  default = ["10.240.0.10", "10.240.0.11", "10.240.0.12"]
}

# Kubernetes worker node IPs within our subnet
variable "worker-ips" {
  type    = list(string)
  default = ["10.240.0.20", "10.240.0.21", "10.240.0.22"]
}

# Use locals to store a var within another var. 
locals {
  ec2_conf = {
    count         = 3
    ami           = "${var.instance_conf["ami"]}"
    instance_type = "${var.instance_conf["instance-type"]}"
  }
}

# Network interface for our kubernetes control nodes - set the IPs defined above to this.
# We will be connecting this to our EC2 control node instance to enable internal networking 
resource "aws_network_interface" "control-plane" {
  subnet_id = aws_subnet.my-subnet.id

  count       = length(var.control-ips)
  private_ips = [var.control-ips[count.index]]

  tags = {
    Name = "control-plane-nw-${count.index}"
  }
}

# Network interface for our worker nodes - set the IPs defined in the variable above to this.
# We will be connecting this to our EC2 control node instance to enable internal networking 
resource "aws_network_interface" "worker-node" {
  subnet_id = aws_subnet.my-subnet.id

  count       = length(var.worker-ips)
  private_ips = [var.worker-ips[count.index]]

  tags = {
    Name = "worker-node-nw-${count.index}"
  }
}

# Set up an EC2 instance for each control node we've defined (3 in our case).
resource "aws_instance" "control-plane-ec2" {
  ami           = local.ec2_conf.ami
  instance_type = local.ec2_conf.instance_type

  count = local.ec2_conf.count

  network_interface {
    network_interface_id = aws_network_interface.control-plane[count.index].id
    device_index         = 0
  }

  tags = {
    "Name" = "control-node-kubernetes-${count.index}"
  }
}

# Set up an EC2 instance for each worker node we've defined (3 in our case).
resource "aws_instance" "worker-nodes-ec2" {
  ami           = local.ec2_conf.ami
  instance_type = local.ec2_conf.instance_type

  count = local.ec2_conf.count

  network_interface {
    network_interface_id = aws_network_interface.worker-node[count.index].id
    device_index         = 0
  }

  tags = {
    "Name" = "worker-nodes-kubernetes-${count.index}"
  }
}


# All output values to be thrown here

# Network Load Balancer DNS Name output
output "nlb_dns" {
  value = aws_lb.my-nlb.dns_name
}
