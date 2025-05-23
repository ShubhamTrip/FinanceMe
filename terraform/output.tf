
output "test_server_ip" {
  description = "Public IP of the test server"
  value       = aws_instance.test_server.public_ip
}

output "prod_server_ip" {
  description = "Public IP of the prod server"
  value       = var.environment == "prod" ? aws_instance.prod_server[0].public_ip : null
}