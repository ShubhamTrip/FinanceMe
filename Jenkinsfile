pipeline {
    agent any
    environment {
        AWS_ACCESS_KEY_ID     = credentials('aws_cred')
        AWS_SECRET_ACCESS_KEY = credentials('aws_cred')
        DOCKER_HUB_CREDENTIALS = credentials('dockerhub_id')
        SSH_PRIVATE_KEY = credentials('jenkins-ssh-key')
    }
    stages {
        // Stage 1: Checkout Code
        stage('Cloning Repo') {
            steps {
                git branch: 'master', url: 'https://github.com/ShubhamTrip/FinanceMe.git'
            }
        }

        // Stage 2: Build & Test
        stage('Build & Test') {
            steps {
                sh 'mvn clean package'
                sh 'mvn test'  // Runs JUnit tests
                sh 'mvn verify -Pintegration-test'  // API tests
            }
            post {
                always {
                    junit '**/target/surefire-reports/*.xml'  // Publish test reports
                }
            }
        }

        // Stage 3: Build Docker Image
        stage('Containerize') {
            steps {
                script {
                    docker.build("financeme/account-service:${env.BUILD_ID}")
                }
            }
        }
        stage('Docker Push') {
            steps {
               withCredentials([usernamePassword(credentialsId: 'dockerhub_id', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
               sh '''
                  echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                  docker tag financeme/account-service:${BUILD_ID} shubhamtrip16/account-service:${BUILD_ID}
                  docker push shubhamtrip16/account-service:${BUILD_ID}
                   '''
                }
              }
        }
        // Stage 4: Configure Test Server (Ansible)
        stage('Provision Test Server') {
            steps {
                sh '''
                    # Generate a new SSH key pair
                    mkdir -p /var/lib/jenkins/.ssh
                    chmod 700 /var/lib/jenkins/.ssh
                    
                    # Generate new key if it doesn't exist
                    if [ ! -f /var/lib/jenkins/.ssh/jenkins_financeme_key ]; then
                        ssh-keygen -t rsa -b 2048 -f /var/lib/jenkins/.ssh/jenkins_financeme_key -N "" -m PEM
                        echo "Generated new SSH key pair"
                    fi
                    
                    chmod 600 /var/lib/jenkins/.ssh/jenkins_financeme_key
                    chmod 644 /var/lib/jenkins/.ssh/jenkins_financeme_key.pub
                    
                    echo "Public key to be used:"
                    cat /var/lib/jenkins/.ssh/jenkins_financeme_key.pub
                    
                    echo "Local key fingerprints (both formats):"
                    ssh-keygen -l -f /var/lib/jenkins/.ssh/jenkins_financeme_key
                    ssh-keygen -E md5 -l -f /var/lib/jenkins/.ssh/jenkins_financeme_key
                '''
                
                dir('terraform') {
                    sh '''
                        # Delete existing key pair if it exists
                        KEY_NAME="financeme-key-test"
                        echo "Checking for existing key pair: $KEY_NAME"
                        if aws ec2 describe-key-pairs --key-names "$KEY_NAME" 2>/dev/null; then
                            echo "Deleting existing key pair"
                            aws ec2 delete-key-pair --key-name "$KEY_NAME"
                        fi
                        
                        # Use the generated public key for terraform
                        terraform init
                        
                        # Force replacement of key pair and instance
                        terraform apply -auto-approve \
                        -var="environment=test" \
                        -var="public_key=$(cat /var/lib/jenkins/.ssh/jenkins_financeme_key.pub)" \
                        -replace="aws_key_pair.finance_me_key" \
                        -replace="aws_instance.test_server"
                        
                        # Get instance details
                        INSTANCE_ID=$(terraform output -raw test_server_instance_id)
                        echo "Instance ID: $INSTANCE_ID"
                        
                        # Wait for instance to be running and status checks to pass
                        echo "Waiting for instance to be running..."
                        aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
                        
                        echo "Waiting for instance status checks..."
                        aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID"
                        
                        # Get instance details including AMI ID
                        echo "Instance details:"
                        AMI_ID=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
                            --query 'Reservations[0].Instances[0].ImageId' --output text)
                        
                        echo "AMI ID: $AMI_ID"
                        
                        # Get AMI details to determine default user
                        AMI_NAME=$(aws ec2 describe-images --image-ids "$AMI_ID" \
                            --query 'Images[0].Name' --output text)
                        
                        echo "AMI Name: $AMI_NAME"
                        
                        # Determine SSH user based on AMI name
                        SSH_USER="ec2-user"  # Default to ec2-user
                        if [[ "$AMI_NAME" == *"ubuntu"* ]]; then
                            SSH_USER="ubuntu"
                        elif [[ "$AMI_NAME" == *"debian"* ]]; then
                            SSH_USER="admin"
                        elif [[ "$AMI_NAME" == *"centos"* ]]; then
                            SSH_USER="centos"
                        fi
                        
                        echo "Using SSH user: $SSH_USER"
                        
                        # Export the SSH user for use in inventory
                        echo "SSH_USER=$SSH_USER" > ssh_config
                        
                        # Install Python 3.8 on the instance
                        echo "Installing Python 3.8 on the instance..."
                        ssh -i /var/lib/jenkins/.ssh/jenkins_financeme_key \
                            -o StrictHostKeyChecking=no \
                            -o UserKnownHostsFile=/dev/null \
                            $SSH_USER@$(terraform output -raw test_server_ip) \
                            'sudo amazon-linux-extras enable python3.8 && \
                             sudo yum install -y python3.8 && \
                             sudo alternatives --set python3 /usr/bin/python3.8'
                    '''
                }

                // Generate inventory file dynamically
                sh '''
                    mkdir -p ansible/inventory/
                    TEST_SERVER_IP=$(cd terraform && terraform output -raw test_server_ip)
                    SSH_USER=$(cd terraform && cat ssh_config | grep SSH_USER | cut -d= -f2)
                    
                    echo "Creating inventory with IP: $TEST_SERVER_IP and user: $SSH_USER"
                    
                    cat > ansible/inventory/test-hosts.yml << EOL
---
all:
  hosts:
    test-server:
      ansible_host: $TEST_SERVER_IP
      ansible_user: $SSH_USER
      ansible_ssh_private_key_file: /var/lib/jenkins/.ssh/jenkins_financeme_key
      ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -v'
      ansible_python_interpreter: /usr/bin/python3.8
EOL

                    echo "Testing SSH connection with retries..."
                    MAX_RETRIES=5
                    RETRY_COUNT=0
                    
                    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
                        echo "Attempt $((RETRY_COUNT + 1)) of $MAX_RETRIES"
                        
                        if [ $RETRY_COUNT -gt 0 ]; then
                            sleep 30
                        fi
                        
                        # Try SSH connection with verbose output
                        if ssh -v -i /var/lib/jenkins/.ssh/jenkins_financeme_key \
                           -o StrictHostKeyChecking=no \
                           -o UserKnownHostsFile=/dev/null \
                           -o ConnectTimeout=10 \
                           $SSH_USER@$TEST_SERVER_IP 'echo "SSH connection successful"; id; whoami'; then
                            echo "SSH connection successful!"
                            break
                        else
                            echo "Connection attempt $((RETRY_COUNT + 1)) failed"
                            echo "Local key fingerprints:"
                            ssh-keygen -l -f /var/lib/jenkins/.ssh/jenkins_financeme_key
                            ssh-keygen -E md5 -l -f /var/lib/jenkins/.ssh/jenkins_financeme_key
                            echo "AWS key fingerprint:"
                            aws ec2 describe-key-pairs --key-names "financeme-key-test" --query 'KeyPairs[0].KeyFingerprint' --output text
                            
                            # Get instance console output for debugging
                            echo "Instance console output:"
                            aws ec2 get-console-output --instance-id $(cd terraform && terraform output -raw test_server_instance_id)
                        fi
                        
                        RETRY_COUNT=$((RETRY_COUNT + 1))
                    done
                    
                    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
                        echo "SSH connection failed after $MAX_RETRIES attempts"
                        exit 1
                    fi
                '''
            }
        }

        // Stage 5: Deploy to Test Server
        stage('Deploy to Test') {
            steps {
                ansiblePlaybook(
                    playbook: 'ansible/app-deploy.yml',
                    inventory: 'ansible/inventory/test-hosts.yml',
                    extraVars: [
                        'docker_image': "financeme/account-service:${env.BUILD_ID}"
                    ]
                )
            }
        }

        // Stage 6: Run Automated Tests (Selenium)
        stage('UI Tests') {
            steps {
                sh 'mvn test -Pselenium-tests'  // Runs Selenium tests
            }
        }

        // Stage 7: Deploy to Prod (If Tests Pass)
        stage('Deploy to Prod') {
            when {
                expression { currentBuild.resultIsBetterOrEqualTo('SUCCESS') }
            }
            steps {
                dir('terraform') {
                    sh 'terraform apply -auto-approve -var="environment=prod"'
                    // Generate inventory file dynamically for prod
                    sh '''
                        SERVER_IP=$(terraform output -raw prod_server_ip)
                        cat > ../ansible/inventory/prod-hosts.yml << EOL
---
all:
  hosts:
    prod-server:
      ansible_host: $SERVER_IP
      ansible_user: ubuntu
      ansible_ssh_private_key_file: /var/lib/jenkins/.ssh/jenkins_financeme_key
      ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
EOL
                    '''
                }
                ansiblePlaybook(
                    playbook: 'ansible/app-deploy.yml',
                    inventory: 'ansible/inventory/prod-hosts.yml',
                    extraVars: [
                        'docker_image': "financeme/account-service:${env.BUILD_ID}"
                    ]
                )
            }
        }
    }
    post {
        always {
            // Clean up sensitive files
            sh 'rm -f /var/lib/jenkins/.ssh/jenkins_financeme_key*'
        }
    }
}
