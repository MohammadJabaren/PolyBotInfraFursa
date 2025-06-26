# add vpc
module "polybot_service_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "${var.username}-polybot-k8s-vpc"
  cidr = "10.0.0.0/16"

  azs             = var.azs
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway   = false

  tags = {
    Name = "${var.username}-polybot-k8s-vpc"
    Env  = var.env
  }
}
# create the aws DynamoDb table of prediction objects
resource "aws_dynamodb_table" "prediction_objects" {
  name           = "Jabaren_${var.env}_prediction_objects"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "uid"

  attribute {
    name = "uid"
    type = "S"
  }
}
# create the aws DynamoDb table of detections objects
resource "aws_dynamodb_table" "detection_objects" {
  name           = "Jabaren_${var.env}_detection_objects"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "prediction_uid"
  range_key      = "label_score"
  attribute {
    name = "prediction_uid"
    type = "S"
  }
  attribute {
    name = "label_score"
    type = "S"
  }
  attribute {
    name = "label"
    type = "S"
  }

  attribute {
    name = "score"
    type = "N"
  }

  attribute {
    name = "score_partition"
    type = "S"
  }

  global_secondary_index {
    name               = "LabelScoreIndex"
    hash_key           = "label"
    range_key          = "score"
    projection_type    = "ALL"
  }

  global_secondary_index {
    name               = "score_partition-score-index"
    hash_key           = "score_partition"
    range_key          = "score"
    projection_type    = "ALL"
  }
}
# create sqs to send to yolo via it
resource "aws_sqs_queue" "sqs" {
  name = "Jabaren_sqs_${var.env}"
}
# create s3 to save the images
resource "aws_s3_bucket" "s3" {
  bucket = "jabaren-polybot-images-${var.env}"

  force_destroy = true

  tags = {
    Environment = var.env
    Project     = "polybot-k8s"
  }
}
#create security group for control panel
resource "aws_security_group" "cp_sg" {
  name        = "Jabaren_control_plane_sg"
  description = "Control plane security group"
  vpc_id      = module.polybot_service_vpc.vpc_id

  # Allow SSH from anywhere
  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
# allow outbound for all
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "control_plane_sg"
    Env  = var.env
  }
}
# create security group for the nodes
resource "aws_security_group" "node_sg" {
  name        = "Jabaren-node-sg"
  description = "Security group for EC2 nodes"
  vpc_id      = module.polybot_service_vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # allow SSH (change this in production!)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}
# create iam role
resource "aws_iam_role" "polybot_role" {
  name = "Jabaren_project_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"  # or "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# create policy for s3
resource "aws_iam_policy" "s3_policy" {
  name        = "Jabaren_s3_policy"
  description = "Allow S3 access for Jabaren"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      Effect   = "Allow",
      Resource = "${aws_s3_bucket.s3.arn}/*"
    }]
  })
}
# create policy for sqs
resource "aws_iam_policy" "sqs_policy" {
  name        = "Jabaren_sqs_policy"
  description = "Allow SQS access for Jabaren"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      Effect   = "Allow",
      Resource = aws_sqs_queue.sqs.arn
    }]
  })
}
# create policy for Dynamodb
resource "aws_iam_policy" "dynamodb_policy" {
  name        = "Jabaren_dynamodb_policy"
  description = "Allow DynamoDB access for Jabaren"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ],
      Effect   = "Allow",
      Resource = [
          aws_dynamodb_table.prediction_objects.arn,
          aws_dynamodb_table.detection_objects.arn,
          "${aws_dynamodb_table.detection_objects.arn}/index/*"
        ]
    }]
  })
}
# attach the s3 policy to the iam role
resource "aws_iam_role_policy_attachment" "attach_s3" {
  role       = aws_iam_role.polybot_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}
# attach the sqs policy to the iam role
resource "aws_iam_role_policy_attachment" "attach_sqs" {
  role       = aws_iam_role.polybot_role.name
  policy_arn = aws_iam_policy.sqs_policy.arn
}
# attach the Dynamodb policy to the iam role
resource "aws_iam_role_policy_attachment" "attach_dynamodb" {
  role       = aws_iam_role.polybot_role.name
  policy_arn = aws_iam_policy.dynamodb_policy.arn
}
# create profile to iam that to connnect the iam role to instances
resource "aws_iam_instance_profile" "polybot_Iam_profile" {
  name = "Jabaren_Iam_profile"
  role = aws_iam_role.polybot_role.name
}
# create ec2 control panel
resource "aws_instance" "control_panel" {
  ami                         = var.ami_id  # Pass your AMI ID as a variable
  instance_type               = "t3.medium"
  subnet_id                   = module.polybot_service_vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.cp_sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.polybot_Iam_profile.name

  user_data = <<-EOF
                #!/bin/bash
                KUBERNETES_VERSION=v1.32

                apt-get update
                apt-get install -y jq unzip ebtables ethtool

                curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                unzip awscliv2.zip
                sudo ./aws/install

                echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/k8s.conf
                sysctl --system

                mkdir -p /etc/apt/keyrings
                curl -fsSL https://pkgs.k8s.io/core:/stable:/$${KUBERNETES_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
                echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$${KUBERNETES_VERSION}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list

                curl -fsSL https://pkgs.k8s.io/addons:/cri-o:/prerelease:/main/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
                echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://pkgs.k8s.io/addons:/cri-o:/prerelease:/main/deb/ /" > /etc/apt/sources.list.d/cri-o.list

                apt-get update
                apt-get install -y software-properties-common apt-transport-https ca-certificates curl gpg
                apt-get install -y cri-o kubelet kubeadm kubectl
                apt-mark hold kubelet kubeadm kubectl

                systemctl start crio.service
                systemctl enable --now crio.service
                systemctl enable --now kubelet

                swapoff -a
                (crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab -
                EOF


  tags = {
    Name = "Jabaren_control_panel"
    Role = "control-panel"
    Env  = var.env
  }
}



