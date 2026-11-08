hcl
resource "aws_instance" "app_node" {
  ami                    = var.ami_id          # Amazon Linux 2023, free-tier eligible
  instance_type          = "t3.micro"          # free tier: 750 hrs/month for 12 months
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.sg_id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.app_profile.name

  user_data = file("${path.module}/bootstrap.sh")

  tags = { Name = "${var.env}-app-node" }
}

# IAM role ≈ Azure Managed Identity + RBAC role assignment
resource "aws_iam_role" "app_role" {
  name = "${var.env}-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_pull" {
  role       = aws_iam_role.app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "${var.env}-app-profile"
  role = aws_iam_role.app_role.name
}