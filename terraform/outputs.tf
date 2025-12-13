output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_eip.crm.public_ip
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.crm.repository_url
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.crm.id
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh -i ~/.ssh/id_ed25519 ubuntu@${aws_eip.crm.public_ip}"
}
