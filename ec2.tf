provider "aws" {
  access_key = "AKIA4GJ7ISRD25DIDV6N"
  secret_key = "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"
  region     = "ap-south-1"
  version    = "v2.70.0"
}

data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

resource "aws_vpc" "test-vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = "true"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.test-vpc.id}"
}

resource "aws_subnet" "public-subnet" {
  vpc_id                  = "${aws_vpc.test-vpc.id}"
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = "true"
}

resource "aws_subnet" "private-subnet" {
  vpc_id                  = "${aws_vpc.test-vpc.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = "false"
}

resource "aws_subnet" "public-subnet1" {
  vpc_id                  = "${aws_vpc.test-vpc.id}"
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = "true"
}


resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat" {
  allocation_id = "${aws_eip.nat_eip.id}"
  subnet_id     = "${aws_subnet.public-subnet.id}"
}

resource "aws_route_table" "rtb" {
  vpc_id = "${aws_vpc.test-vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }
}

resource "aws_route_table" "prvtrtb" {
  vpc_id = "${aws_vpc.test-vpc.id}"

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.nat.id}"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = "${aws_subnet.public-subnet.id}"
  route_table_id = "${aws_route_table.rtb.id}"
}

resource "aws_route_table_association" "private" {
  subnet_id      = "${aws_subnet.private-subnet.id}"
  route_table_id = "${aws_route_table.prvtrtb.id}"
}

resource "aws_security_group" "sg" {
  name   = "sg"
  vpc_id = "${aws_vpc.test-vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    // This means, all ip address are allowed to ssh !
    // Do not do it in the production.
    // Put your office or home address in it!
    cidr_blocks = ["0.0.0.0/0"]
  }

  //If you do not add this rule, you can not reach the NGIX
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "lb-sg" {
  name   = "lb-sg"
  vpc_id = "${aws_vpc.test-vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "tcp"

    // This means, all ip address are allowed to ssh !
    // Do not do it in the production.
    // Put your office or home address in it!
    cidr_blocks = ["0.0.0.0/0"]
  }

  //If you do not add this rule, you can not reach the NGIX
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "test-ec2" {
  ami                    = "${data.aws_ssm_parameter.ami.value}"
  instance_type          = "t2.micro"
  subnet_id              = "${aws_subnet.public-subnet.id}"
  vpc_security_group_ids = ["${aws_security_group.sg.id}"]
}

resource "aws_lb" "lb" {
  name               = "test-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.lb-sg.id}"]
  subnets            = ["${aws_subnet.public-subnet.id}","${aws_subnet.public-subnet1.id}"]

  enable_deletion_protection =false
}

resource "aws_lb_target_group" "lb-tg" {
  name     = "lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.test-vpc.id}"
}

resource "aws_lb_listener" "lb-lsn" {
  load_balancer_arn = "${aws_lb.lb.arn}"
  port              = "443"
  protocol          = "HTTPS"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.lb-tg.arn}"
  }
}

resource "aws_lb_target_group_attachment" "test" {
  target_group_arn = "${aws_lb_target_group.lb-tg.arn}"
  target_id        = "${aws_instance.test-ec2.id}"
  port             = 80
}