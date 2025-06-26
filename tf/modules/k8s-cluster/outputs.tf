output "control_plane_ip" {
  value = aws_instance.control_panel.public_ip
  description = "Public IP of the control plane EC2 instance"
}