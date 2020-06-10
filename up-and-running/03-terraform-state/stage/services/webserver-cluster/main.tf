provider "aws" {
    region = "eu-west-1"
}

terraform {
    backend "s3" {

        bucket          = "terraform-state-m1r5h"
        key             = "stage/services/webserver-cluster/terraform.tfstate"
        region          = "eu-west-1"

        dynamodb_table  = "terraform-locks-m1r5h"
        encrypt         = "true"
    }
}


resource "aws_launch_configuration" "example02" {
    image_id            = "ami-0701e7be9b2a77600"
    instance_type       = "t2.micro"
    security_groups     = [aws_security_group.example02instance.id]

    user_data = <<-EOF
                #!/bin/bash
                echo "Hello, World" > index.html
                nohup busybox httpd -f -p ${var.server_port} &
                EOF


    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_autoscaling_group" "example02" {
    launch_configuration = aws_launch_configuration.example02.name
    vpc_zone_identifier  = data.aws_subnet_ids.default.ids

    target_group_arns = [aws_lb_target_group.asg.arn]  # Point at target group
    health_check_type = "ELB"

    min_size = 2
    max_size = 5

    tag {
        key         = "Name"
        value       = "terraform-asg-example02"
        propagate_at_launch = true
    }

}

resource "aws_lb" "example02" {
   
    name = "terraform-asg-example"
    load_balancer_type = "application"
    subnets = data.aws_subnet_ids.default.ids
    security_groups = [aws_security_group.alb.id] # Required, inbound/outbound denied by default

}

resource "aws_lb_listener" "http" { # Configured to listen to HTTP
    load_balancer_arn = aws_lb.example02.arn
    port              = 80
    protocol          = "HTTP"

    default_action {
        type = "fixed-response"
    

    fixed_response {
        content_type = "text/plain"
        message_body = "404: Page not found"
        status_code  = 404
    }
    }
}

resource "aws_security_group" "alb" {
    name = "terraform-example-alb"

    # Allow inbound HTTP requests
    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # Allow all outbound requests
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    field  = "path-pattern"
    values = ["*"]
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}


resource "aws_lb_target_group" "asg" {
  name     = "terraform-asg-example"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}



resource "aws_security_group" "example02instance" {
    name = "terraform-example02-instance"

    ingress {
        from_port   = var.server_port
        to_port     = var.server_port
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
}


data "aws_vpc" "default" {
  default = true
}


data "aws_subnet_ids" "default" {
    vpc_id = data.aws_vpc.default.id
}
