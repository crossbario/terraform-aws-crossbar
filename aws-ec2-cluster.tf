# Copyright (c) Crossbar.io Technologies GmbH. Licensed under GPL 3.0.

# https://www.terraform.io/docs/providers/aws/r/launch_configuration.html
resource "aws_launch_configuration" "crossbarfx_cluster_launchconfig" {
    name_prefix     = "crossbarfx_cluster_launchconfig"
    image_id        = var.aws-amis[var.aws-region]
    instance_type   = var.dataplane-instance-type

    key_name        = aws_key_pair.crossbarfx_keypair.key_name
    security_groups = [
        aws_security_group.crossbarfx_cluster_node.id
    ]

    user_data = templatefile("${path.module}/files/setup-edge.sh", {
            file_system_id = aws_efs_file_system.crossbarfx_efs.id,
            access_point_id_nodes = aws_efs_access_point.crossbarfx_efs_nodes.id
            master_url = "ws://${aws_instance.crossbarfx_node_master[0].private_ip}:${var.master-port}/ws"
            master_hostname = aws_instance.crossbarfx_node_master[0].private_ip
            master_port = var.master-port
    })
}

# https://www.terraform.io/docs/providers/aws/r/autoscaling_group.html
resource "aws_autoscaling_group" "crossbarfx_cluster_autoscaling" {
    name                      = "crossbarfx_cluster_autoscaling"
    launch_configuration      = aws_launch_configuration.crossbarfx_cluster_launchconfig.name

    vpc_zone_identifier       = [
        aws_subnet.crossbarfx_vpc_public1.id,
        aws_subnet.crossbarfx_vpc_public2.id,
        aws_subnet.crossbarfx_vpc_public3.id
    ]
    # load_balancers            = [
    #     aws_lb.crossbarfx-nlb.name
    # ]
    # target_group_arns = []

    min_size                  = var.dataplane-min-size
    max_size                  = var.dataplane-max-size
    desired_capacity          = var.dataplane-desired-size

    health_check_grace_period = 300
    health_check_type         = "EC2"

    tag {
        key                 = "Name"
        value               = "Crossbar.io FX (Edge)"
        propagate_at_launch = true
    }
    tag {
        key                 = "node"
        value               = "edge"
        propagate_at_launch = true
    }
    tag {
        key                 = "env"
        value               = "prod"
        propagate_at_launch = true
    }
}

# https://www.terraform.io/docs/providers/aws/r/autoscaling_policy.html
resource "aws_autoscaling_policy" "crossbarfx_cluster_cpu_policy" {
    name                   = "crossbarfx_cluster_cpu_policy"
    autoscaling_group_name = aws_autoscaling_group.crossbarfx_cluster_autoscaling.name
    adjustment_type        = "ChangeInCapacity"
    scaling_adjustment     = "1"
    cooldown               = "300"
    policy_type            = "SimpleScaling"
}

# https://www.terraform.io/docs/providers/aws/r/cloudwatch_metric_alarm.html
resource "aws_cloudwatch_metric_alarm" "crossbarfx_cluster_cpu_alarm" {
    alarm_name          = "crossbarfx_cluster_cpu-alarm"
    alarm_description   = "crossbarfx_cluster_cpu-alarm"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods  = "2"
    metric_name         = "CPUUtilization"
    namespace           = "AWS/EC2"
    period              = "120"
    statistic           = "Average"
    threshold           = "60"

    dimensions = {
        "AutoScalingGroupName" = aws_autoscaling_group.crossbarfx_cluster_autoscaling.name
    }

    actions_enabled = true
    alarm_actions   = [aws_autoscaling_policy.crossbarfx_cluster_cpu_policy.arn]
}

#
# scale down alarm
#

# https://www.terraform.io/docs/providers/aws/r/autoscaling_policy.html
resource "aws_autoscaling_policy" "crossbarfx_cluster_cpu_policy_scaledown" {
    name                   = "crossbarfx_cluster_cpu_olicy_scaledown"
    autoscaling_group_name = aws_autoscaling_group.crossbarfx_cluster_autoscaling.name
    adjustment_type        = "ChangeInCapacity"
    scaling_adjustment     = "-1"
    cooldown               = "300"
    policy_type            = "SimpleScaling"
}

# https://www.terraform.io/docs/providers/aws/r/cloudwatch_metric_alarm.html
resource "aws_cloudwatch_metric_alarm" "crossbarfx_cluster_cpu_alarm_scaledown" {
    alarm_name          = "crossbarfx_cluster_cpu_alarm_scaledown"
    alarm_description   = "crossbarfx_cluster_cpu_alarm_scaledown"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods  = "2"
    metric_name         = "CPUUtilization"
    namespace           = "AWS/EC2"
    period              = "120"
    statistic           = "Average"
    threshold           = "10"

    dimensions = {
        "AutoScalingGroupName" = aws_autoscaling_group.crossbarfx_cluster_autoscaling.name
    }

    actions_enabled = true
    alarm_actions   = [aws_autoscaling_policy.crossbarfx_cluster_cpu_policy_scaledown.arn]
}