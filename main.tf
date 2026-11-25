# -----------------------------------------------------------------------------
# Lookups
# -----------------------------------------------------------------------------

# AZs that offer the web server instance type, sorted so the choice is stable.
data "aws_ec2_instance_type_offerings" "web" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

locals {
  azs = slice(sort(data.aws_ec2_instance_type_offerings.web.locations), 0, 2)
}

# Latest Amazon Linux 2023 AMI (the CorpWeb user data uses dnf).
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# -----------------------------------------------------------------------------
# Network: VPC, one public + one private subnet in each of two AZs
# -----------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "seis616-tf-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "seis616-tf-igw" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = local.azs[0]
  map_public_ip_on_launch = true

  tags = { Name = "seis616-tf-public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = local.azs[1]
  map_public_ip_on_launch = true

  tags = { Name = "seis616-tf-public-b" }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = local.azs[0]

  tags = { Name = "seis616-tf-private-a" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = local.azs[1]

  tags = { Name = "seis616-tf-private-b" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "seis616-tf-public-rt" }
}

# Private route table: local route only (no NAT gateway).
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "seis616-tf-private-rt" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# Security groups
# Terraform removes AWS's default allow-all egress rule, so egress is explicit.
# -----------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "seis616-tf-alb-sg"
  description = "Load balancer: HTTP from anywhere"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_web" {
  security_group_id            = aws_security_group.alb.id
  description                  = "HTTP to the web servers"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.web.id
}

resource "aws_security_group" "web" {
  name        = "seis616-tf-web-sg"
  description = "Web servers: HTTP from anywhere"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "web_http" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP from anywhere"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "web_all" {
  security_group_id = aws_security_group.web.id
  description       = "All outbound (dnf, S3, SSM, MySQL)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "db" {
  name        = "seis616-tf-db-sg"
  description = "RDS MySQL: 3306 from the web servers only"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "db_mysql_from_web" {
  security_group_id            = aws_security_group.db.id
  description                  = "MySQL from the web servers' security group only"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.web.id
}

# -----------------------------------------------------------------------------
# Web servers: one in each public subnet
# -----------------------------------------------------------------------------

resource "aws_iam_role" "web" {
  name = "seis616-tf-web-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# SSM: shell access for the database connectivity test, no key pair or port 22.
resource "aws_iam_role_policy_attachment" "web_ssm" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# The user data copies index.php from the course bucket.
resource "aws_iam_role_policy" "web_s3_read" {
  name = "read-seis665-public"
  role = aws_iam_role.web.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = "arn:aws:s3:::seis665-public/*"
    }]
  })
}

resource "aws_iam_instance_profile" "web" {
  name = "seis616-tf-web-profile"
  role = aws_iam_role.web.name
}

resource "aws_instance" "web1" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name
  user_data              = file("${path.module}/user_data.sh")

  tags = { Name = var.instance1_name }

  # Boot only after the public route exists, or user data can't reach dnf/S3.
  depends_on = [aws_route_table_association.public_a, aws_route_table_association.public_b]

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_instance" "web2" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_b.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name
  user_data              = file("${path.module}/user_data.sh")

  tags = { Name = var.instance2_name }

  depends_on = [aws_route_table_association.public_a, aws_route_table_association.public_b]

  lifecycle {
    ignore_changes = [ami]
  }
}

# -----------------------------------------------------------------------------
# Database: RDS MySQL in the private subnets
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "mysql" {
  name        = "seis616-tf-db-subnets"
  description = "All private subnets"
  subnet_ids  = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

resource "aws_db_instance" "mysql" {
  identifier     = "seis616-tf-mysql"
  engine         = "mysql"
  engine_version = "8.4"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp2"
  storage_encrypted = true

  username                    = "admin"
  manage_master_user_password = true # password lives in Secrets Manager, not in code

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false

  # Teardown-friendly: no final snapshot or retained backups.
  backup_retention_period  = 0
  delete_automated_backups = true
  skip_final_snapshot      = true
  deletion_protection      = false
}

# -----------------------------------------------------------------------------
# Load balancer: distributes requests across both web servers
# -----------------------------------------------------------------------------

resource "aws_lb" "web" {
  name               = "seis616-tf-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  depends_on = [aws_route_table_association.public_a, aws_route_table_association.public_b]
}

resource "aws_lb_target_group" "web" {
  name     = "seis616-tf-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path    = "/"
    matcher = "200"
  }
}

resource "aws_lb_target_group_attachment" "web1" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "web2" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web2.id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
