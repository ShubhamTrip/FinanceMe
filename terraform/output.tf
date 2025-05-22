
output "instance_public_ip" {
  value = aws_instance.finance_me_ec2.public_ip
}
output "instance_id" {
  value = aws_instance.finance_me_ec2.id
}
output "instance_private_ip" {
  value = aws_instance.finance_me_ec2.private_ip
}