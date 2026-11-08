hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.env}-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block               = var.subnet_cidr
  map_public_ip_on_launch  = true
  availability_zone        = var.az
  tags = { Name = "${var.env}-public-subnet" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.rt.id
}

# Security Group ≈ Azure NSG
resource "aws_security_group" "app_sg" {
  name   = "${var.env}-app-sg"
  vpc_id = aws_vpc.main.id

  ingress { from_port = 22   to_port = 22   protocol = "tcp" cidr_blocks = [var.admin_cidr] }   # SSH — lock to your IP
  ingress { from_port = 6443 to_port = 6443 protocol = "tcp" cidr_blocks = [var.admin_cidr] }   # k3s API
  ingress { from_port = 30080 to_port = 30080 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }    # app NodePort
  egress  { from_port = 0    to_port = 0    protocol = "-1"  cidr_blocks = ["0.0.0.0/0"] }
}