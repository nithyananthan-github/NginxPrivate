terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
    region = "ca-central-1"
}


# create vpc
resource "aws_vpc" "nginx-tf4-vpc" {
  cidr_block              = "10.0.0.0/16"
  instance_tenancy        = "default"
  enable_dns_hostnames    = true

  tags      = {
    Name    = "nginx-tf4-vpc"
  }
}


# create internet gateway and attach it to vpc
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id    = aws_vpc.nginx-tf4-vpc.id

  tags      = {
    Name    = "nginx-tf4-igw"
  }
}


# use data source to get all avalablility zones in region
data "aws_availability_zones" "available_zones" {}

# create public subnet az1
resource "aws_subnet" "public_subnet_az1" {
  vpc_id                  = aws_vpc.nginx-tf4-vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available_zones.names[0]
  map_public_ip_on_launch = true

  tags      = {
    Name    = "public subnet az1"
  }
}


# create route table and add public route
resource "aws_route_table" "public_route_table" {
  vpc_id       = aws_vpc.nginx-tf4-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags       = {
    Name     = "public route table AZ1 "
  }
}


# associate public subnet az1 to "public route table"
resource "aws_route_table_association" "public_subnet_az1_route_table_association" {
  subnet_id           = aws_subnet.public_subnet_az1.id
  route_table_id      = aws_route_table.public_route_table.id
}


# Create public instance in AZ1
resource "aws_instance" "TerraformPublicInstanceAZ1" {
  ami           = "ami-037d1030a0db1fa12"
  instance_type = "t2.micro"
  key_name = "shyamKey"
  vpc_security_group_ids = [aws_security_group.allow_tls.id]
  subnet_id              = aws_subnet.public_subnet_az1.id
  associate_public_ip_address = true
  tags = {
    Name = "TerraformPublicInstanceAZ1"
  } 

  # user_data = file("userdatehttpd.sh")
  user_data = <<-EOF
        #!/bin/bash
        # Use this for your user data (script without newlines)
        # install httpd (Linux 2 version)
          yum update -y
          yum install -y httpd.x86_64
          systemctl start httpd.service
          systemctl enable httpd.service
          echo "Hello World from public instance AZ1 $(hostname -f)" > /var/www/html/index.html 
        EOF
}


# Create a SG for the Public Instance 
resource "aws_security_group" "allow_tls" {
  name        = "allow_alla"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.nginx-tf4-vpc.id

  ingress {
    description      = "TLS from VPC"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
   # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

    ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
   # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
   # ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_tls_VPC_SG"
  }
}


resource "aws_eip" "lb" {
 # instance = aws_instance.web.id
 # domain   = "vpc"
  vpc = true
}

# associate public instance
resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.TerraformPublicInstanceAZ1.id
  allocation_id = aws_eip.lb.id
}


# create private app subnet az1
resource "aws_subnet" "private_app_subnet_az1" {
  vpc_id                   = aws_vpc.nginx-tf4-vpc.id
  cidr_block               = "10.0.2.0/24"
  availability_zone        = data.aws_availability_zones.available_zones.names[0]
  map_public_ip_on_launch  = false

  tags      = {
    Name    = "private subnet az1"
  }
}

resource "aws_eip" "terraform-eip" {
  #instance = aws_instance.web.id
  vpc      = true
}

resource "aws_nat_gateway" "terraform_natgw" {
  subnet_id     = aws_subnet.public_subnet_az1.id
  allocation_id = aws_eip.terraform-eip.id
  tags = {
    Name = "Terraform NAT gateway AZ1"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  # depends_on = [aws_internet_gateway.example]
}

# create route table and add private route
resource "aws_route_table" "private_route_table" {
  vpc_id       = aws_vpc.nginx-tf4-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.terraform_natgw.id
  }

  tags       = {
    Name     = "private route table AZ1"
  }
}

# associate private subnet az1 to "private route table"
resource "aws_route_table_association" "private_subnet_az1_route_table_association" {
  subnet_id           = aws_subnet.private_app_subnet_az1.id
  route_table_id      = aws_route_table.private_route_table.id
}

# Create Private instance in AZ1
resource "aws_instance" "TerraformPrivateInstanceAZ1" {
  ami           = "ami-037d1030a0db1fa12"
  instance_type = "t2.micro"
  key_name = "shyamKey"
  vpc_security_group_ids = [aws_security_group.allow_tls_private.id]
  subnet_id              = aws_subnet.private_app_subnet_az1.id
  associate_public_ip_address = false
  tags = {
    Name = "Terraform Private Instance AZ1"
  } 

  # user_data = file("userdatehttpd.sh")
  user_data = <<-EOF
       #! /bin/bash
          sudo yum update -y
          sudo yum install nginx
          sudo systemctl start nginx
          sudo systemctl enable nginx
          echo "Hello World from Private instance AZ1 $(hostname -f)" > /var/www/html/index.html 
        EOF
}


# Create a SG for the Private Instance 
resource "aws_security_group" "allow_tls_private" {
  name        = "SG-Private"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.nginx-tf4-vpc.id

  ingress {
    description      = "Allow SSH from Basion Host only"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
     # Allow traffic only from ALB
    security_groups = [aws_security_group.allow_tls.id]
   # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

    ingress {
    description      = "Allow HTTP traffic"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
       # Allow traffic only from ALB
    security_groups = [aws_security_group.SG-ALB.id]
   # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }


    ingress {
    description      = "Allow HTTPS traffic"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
       # Allow traffic only from ALB
    security_groups = [aws_security_group.SG-ALB.id]
   # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]     
   # ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_tls_VPC_SG"
  }
}

# Create a SG for the ALB
resource "aws_security_group" "SG-ALB" {
  name        = "SG-ALB"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.nginx-tf4-vpc.id

    ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
   # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }
    ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
   # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]     
   # ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "ALB_SG"
  }
}

# Create ALB 
resource "aws_lb" "my_alb" {
  name               = "my-alb"
  internal           = false  # Set to true if you want an internal ALB
  load_balancer_type = "application"

  subnets            = [aws_subnet.public_subnet_az1.id,aws_subnet.public_subnet_az2.id]  

  security_groups    = [aws_security_group.SG-ALB.id]

  tags = {
    Name = "My ALB"
  }
}


# Create ALB listeners
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}

# Create Target Group 
resource "aws_lb_target_group" "my_target_group" {
  name        = "my-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.nginx-tf4-vpc.id

  health_check {
    path     = "/"
    protocol = "HTTP"
    port     = "traffic-port"
    matcher  = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "my_instance_attachment" {
  target_group_arn = aws_lb_target_group.my_target_group.arn
  target_id        = aws_instance.TerraformPrivateInstanceAZ1.id
  port             = 80
}






# Create AZ2 and public instance 




# create public subnet az2
resource "aws_subnet" "public_subnet_az2" {
  vpc_id                  = aws_vpc.nginx-tf4-vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = data.aws_availability_zones.available_zones.names[1]
  map_public_ip_on_launch = true

  tags      = {
    Name    = "public subnet az2"
  }
}


# create route table and add public route
resource "aws_route_table" "public_route_table-az2" {
  vpc_id       = aws_vpc.nginx-tf4-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags       = {
    Name     = "public route table AZ2 "
  }
}


# associate public subnet az2 to "public route table"
resource "aws_route_table_association" "public_subnet_az2_route_table_association" {
  subnet_id           = aws_subnet.public_subnet_az2.id
  route_table_id      = aws_route_table.public_route_table-az2.id
}


# Create public instance in AZ2
resource "aws_instance" "TerraformPublicInstanceAZ2" {
  ami           = "ami-037d1030a0db1fa12"
  instance_type = "t2.micro"
  key_name = "shyamKey"
  vpc_security_group_ids = [aws_security_group.allow_tls.id]
  subnet_id              = aws_subnet.public_subnet_az2.id
  associate_public_ip_address = true
  tags = {
    Name = "TerraformPublicInstanceAZ2"
  } 

  # user_data = file("userdatehttpd.sh")
  user_data = <<-EOF
        #!/bin/bash
        # Use this for your user data (script without newlines)
        # install httpd (Linux 2 version)
          yum update -y
          yum install -y httpd.x86_64
          systemctl start httpd.service
          systemctl enable httpd.service
          echo "Hello World from public instance AZ2 $(hostname -f)" > /var/www/html/index.html 
        EOF
}


# Create a SG for the Public Instance 
resource "aws_security_group" "allow_tls-az2" {
  name        = "allow_all-az2"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.nginx-tf4-vpc.id

  ingress {
    description      = "TLS from VPC"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
   # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

    ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
   # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
   # ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_tls_VPC_SG-az2"
  }
}


resource "aws_eip" "lb2" {
 # instance = aws_instance.web.id
 # domain   = "vpc"
  vpc = true
}

# associate public instance
resource "aws_eip_association" "eip_assoc-az2" {
  instance_id   = aws_instance.TerraformPublicInstanceAZ2.id
  allocation_id = aws_eip.lb2.id
}






