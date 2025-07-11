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
  ingress {
  description     = "Allow K8s API server access from worker nodes"
  from_port       = 6443
  to_port         = 6443
  protocol        = "tcp"
  security_groups = [aws_security_group.node_sg.id]
  }
  ingress {
  description     = "Allow K8s API server access from worker nodes"
  from_port       = 8080
  to_port         = 8080
  protocol        = "tcp"
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

resource "aws_security_group_rule" "allow_alb_to_nodeport" {
  type                     = "ingress"
  from_port                = 31080
  to_port                  = 31080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node_sg.id
  source_security_group_id = aws_security_group.alb_sg.id
  description              = "Allow ALB to access NodePort 31080 on worker nodes"
}


resource "aws_security_group_rule" "allow_cp_to_node" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = -1
  security_group_id        = aws_security_group.node_sg.id
  source_security_group_id = aws_security_group.cp_sg.id
  description              = "Allow ALB to access NodePort 31080 on worker nodes"
}

resource "aws_security_group_rule" "allow_node_to_cp" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = -1
  security_group_id        = aws_security_group.cp_sg.id
  source_security_group_id = aws_security_group.node_sg.id
  description              = "Allow ALB to access NodePort 31080 on worker nodes"
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

                sudo apt install -y snapd
                sudo snap install amazon-ssm-agent --classic
                sudo systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
                sudo systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service
                swapoff -a
                (crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab -
                EOF


  tags = {
    Name = "Jabaren_control_panel"
    Role = "control-panel"
    Env  = var.env
  }
}
# create temple to the auto scaling(blueprint)
resource "aws_launch_template" "worker_launch_template" {
  name_prefix   = "Jabaren-worker-template-"
  image_id      = var.ami_id
  instance_type = "t3.medium"
  key_name      = var.key_pair_name

  iam_instance_profile {
    name = aws_iam_instance_profile.polybot_Iam_profile.name
  }

  network_interfaces {
  associate_public_ip_address = true
  security_groups             = [aws_security_group.node_sg.id]
}
block_device_mappings {
    device_name = "/dev/sda1"   # <-- update based on CLI output
    ebs {
      volume_size           = 20      # 20 GiB root volume
      volume_type           = "gp2"
      delete_on_termination = true
    }
}
  user_data = base64encode(file("${path.module}/worker_user_data.sh"))
}

#--------------------------------------------------------- Join use (Lambda + Lifecycle Hook + SNS + SSM)-----------------------------------
resource "aws_sns_topic" "asg_notifications" {
  name = "Jabaren-worker-asg-lifecycle"
}

resource "aws_autoscaling_lifecycle_hook" "worker_join_hook" {
  name                   = "Jabaren-worker-join-hook"
  autoscaling_group_name = aws_autoscaling_group.worker_asg.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
  default_result         = "CONTINUE"
  heartbeat_timeout      = 300
  notification_target_arn = aws_sns_topic.asg_notifications.arn
  role_arn               = aws_iam_role.asg_lifecycle_role.arn
}

resource "aws_iam_role" "asg_lifecycle_role" {
  name = "Jabaren-asg-lifecycle-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Principal = { Service = "autoscaling.amazonaws.com" },
      Effect    = "Allow"
    }]
  })
}

resource "aws_iam_role_policy" "asg_sns" {
  role = aws_iam_role.asg_lifecycle_role.name
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = "sns:Publish",
      Resource = aws_sns_topic.asg_notifications.arn
    }]
  })
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "jabaren-lambda-worker-join"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_exec_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:DescribeInstanceInformation",
          "ssm:GetCommandInvocation",
          "ssm:SendCommand",
          "ssm:ListCommands",
          "ssm:UpdateInstanceInformation",
          "ssmmessages:*",
          "ec2messages:*"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeInstances"  # 🔑 REQUIRED for control-plane lookup
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "autoscaling:CompleteLifecycleAction"  # 🔄 REQUIRED to end lifecycle
        ],
        Resource = "*"
      }
    ]
  })
}



#resource "aws_lambda_function" "worker_join_lambda" {
#  filename         = "lambda_payload.zip"
#  function_name    = "worker-auto-join"
#  role             = aws_iam_role.lambda_exec_role.arn
#  handler          = "bootstrap"  # for container or custom runtime
#  runtime          = "provided.al2"
#  timeout          = 60
#  environment { variables = { REGION = var.region } }
#}
resource "aws_lambda_function" "worker_join_lambda" {
  filename         = "lambda_payload.zip"
  function_name    = "worker-auto-join"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  environment {
    variables = {
      REGION = var.region
    }
  }
}
resource "aws_lambda_permission" "sns_invoke" {
  statement_id  = "AllowSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.worker_join_lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.asg_notifications.arn
}

resource "aws_sns_topic_subscription" "sub" {
  topic_arn = aws_sns_topic.asg_notifications.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.worker_join_lambda.arn
}

resource "aws_iam_policy" "ssm_logs_policy" {
  name = "Jabaren_ssm_logs_policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:DescribeInstanceInformation",
          "ssm:GetCommandInvocation",
          "ssm:SendCommand",
          "ssm:ListCommands"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_ssm_logs" {
  role       = aws_iam_role.polybot_role.name
  policy_arn = aws_iam_policy.ssm_logs_policy.arn
}
resource "aws_iam_policy" "ssm_instance_policy" {
  name        = "Jabaren_ssm_instance_policy"
  description = "Allow EC2 instances to work with SSM"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:DescribeAssociation",
          "ssm:GetDeployablePatchSnapshotForInstance",
          "ssm:GetDocument",
          "ssm:DescribeDocument",
          "ssm:GetManifest",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:PutInventory",
          "ssm:PutComplianceItems",
          "ssm:PutConfigurePackageResult",
          "ssm:UpdateAssociationStatus",
          "ssm:UpdateInstanceAssociationStatus",
          "ssm:UpdateInstanceInformation",
          "ssmmessages:*",
          "ec2messages:*",
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "attach_ssm_instance_policy" {
  role       = aws_iam_role.polybot_role.name
  policy_arn = aws_iam_policy.ssm_instance_policy.arn
}

# create the autoscaling
resource "aws_autoscaling_group" "worker_asg" {
  name                = "Jabaren-worker-asg"
  min_size            = 0
  max_size            = 3
  desired_capacity    = 0
  vpc_zone_identifier = module.polybot_service_vpc.public_subnets
  target_group_arns = [aws_lb_target_group.worker_tg.arn]

  launch_template {
    id      = aws_launch_template.worker_launch_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "Jabaren-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "Env"
    value               = var.env
    propagate_at_launch = true
  }
}

#--------------------------------------------------------------- ALB Init -----------------------------------------------
resource "aws_security_group" "alb_sg" {
  name        = "${var.username}-alb-sg"
  description = "Allow HTTPS"
  vpc_id      = module.polybot_service_vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_target_group" "worker_tg" {
  name        = "${var.username}-target-group"
  port        = 31080                # NodePort
  protocol    = "HTTP"
  vpc_id      = module.polybot_service_vpc.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    interval            = 30
    path                = "/healthz"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb" "worker_alb" {
  name               = "${var.username}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = module.polybot_service_vpc.public_subnets
  security_groups    = [aws_security_group.alb_sg.id]
}

data "aws_route53_zone" "main_zone" {
  name         = "fursa.click"
  private_zone = false
}

resource "aws_route53_record" "url_dev" {
  zone_id = data.aws_route53_zone.main_zone.zone_id
  name    = "jabaren.dev"
  type    = "A"

  alias {
    name                   = aws_lb.worker_alb.dns_name
    zone_id                = aws_lb.worker_alb.zone_id
    evaluate_target_health = true
  }
}


resource "aws_acm_certificate" "cert_dev" {
  domain_name       = "${var.username}.dev.fursa.click"
  validation_method = "DNS"

  tags = {
    Name = "${var.username}.dev.fursa.click"
  }
}

resource "aws_route53_record" "cert_validation_dev" {
  name    = tolist(aws_acm_certificate.cert_dev.domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.cert_dev.domain_validation_options)[0].resource_record_type
  zone_id = data.aws_route53_zone.main_zone.zone_id
  records = [tolist(aws_acm_certificate.cert_dev.domain_validation_options)[0].resource_record_value]
  ttl     = 300
}

resource "aws_acm_certificate_validation" "cert_validation_dev" {
  certificate_arn         = aws_acm_certificate.cert_dev.arn
  validation_record_fqdns = [aws_route53_record.cert_validation_dev.fqdn]
}
#redirect the http to https
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.worker_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.worker_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.cert_validation_dev.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.worker_tg.arn
  }
}






