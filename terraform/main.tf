provider "aws" {
  region = "us-east-1"
}

resource "aws_key_pair" "finance_me_key" {
  key_name   = "financeme-key-${var.environment}"
  public_key = var.public_key
}

resource "tls_private_key" "financeme" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "aws_security_group" "finance_me_sg" {
  name        = "finance_me_sg"
  description = "Allow SSH and app traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # For SSH access (restrict for production)
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # App port open for testing
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "test_server" {
  ami           = "ami-0c02fb55956c7d316"  
  instance_type = "t2.micro"
  key_name      = aws_key_pair.finance_me_key.key_name
  security_groups = [aws_security_group.finance_me_sg.name]
  tags = {
    Name = "FinanceMe-Test-Server"
  }
}

resource "aws_instance" "prod_server" {
  count         = var.environment == "prod" ? 1 : 0
  ami           = "ami-0c02fb55956c7d316"  
  instance_type = "t2.micro"
  key_name      = aws_key_pair.finance_me_key.key_name
  security_groups = [aws_security_group.finance_me_sg.name]
  tags = {
    Name = "FinanceMe-Prod-Server"
  }
}