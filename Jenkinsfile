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
                        ssh-keygen -t rsa -b 4096 -f /var/lib/jenkins/.ssh/jenkins_financeme_key -N ""
                        echo "Generated new SSH key pair"
                    fi
                    
                    chmod 600 /var/lib/jenkins/.ssh/jenkins_financeme_key
                    chmod 644 /var/lib/jenkins/.ssh/jenkins_financeme_key.pub
                    
                    echo "Public key to be used:"
                    cat /var/lib/jenkins/.ssh/jenkins_financeme_key.pub
                '''
                
                dir('terraform') {
                    sh '''
                        # Use the generated public key for terraform
                        terraform init
                        terraform apply -auto-approve \
                        -var="environment=test" \
                        -var="public_key=$(cat /var/lib/jenkins/.ssh/jenkins_financeme_key.pub)"
                    '''
                }

                // Generate inventory file dynamically
                sh '''
                    mkdir -p ansible/inventory/
                    cat > ansible/inventory/test-hosts.yml << EOL
---
all:
  hosts:
    test-server:
      ansible_host: $(cd terraform && terraform output -raw test_server_ip)
      ansible_user: ubuntu
      ansible_ssh_private_key_file: /var/lib/jenkins/.ssh/jenkins_financeme_key
      ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOL

                    echo "Testing SSH connection:"
                    TEST_SERVER_IP=$(cd terraform && terraform output -raw test_server_ip)
                    ssh -v -i /var/lib/jenkins/.ssh/jenkins_financeme_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$TEST_SERVER_IP 'echo SSH connection successful' || {
                        echo "SSH connection failed. Debugging info:"
                        echo "Server IP: $TEST_SERVER_IP"
                        echo "Key fingerprint:"
                        ssh-keygen -l -f /var/lib/jenkins/.ssh/jenkins_financeme_key
                        echo "Public key:"
                        cat /var/lib/jenkins/.ssh/jenkins_financeme_key.pub
                        exit 1
                    }
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
