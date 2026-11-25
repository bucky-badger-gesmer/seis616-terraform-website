output "instance1_public_ip" {
  description = "Public IP address of the first web server"
  value       = aws_instance.web1.public_ip
}

output "instance2_public_ip" {
  description = "Public IP address of the second web server"
  value       = aws_instance.web2.public_ip
}

output "alb_dns_name" {
  description = "DNS name (endpoint) of the application load balancer"
  value       = aws_lb.web.dns_name
}

output "alb_url" {
  description = "URL to reach the website through the load balancer"
  value       = "http://${aws_lb.web.dns_name}"
}

output "rds_endpoint" {
  description = "Endpoint (hostname) of the RDS MySQL database"
  value       = aws_db_instance.mysql.address
}

output "rds_port" {
  description = "Port of the RDS MySQL database"
  value       = aws_db_instance.mysql.port
}
