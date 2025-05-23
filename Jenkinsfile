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
        dir('terraform') {
            sh 'mkdir -p ~/.ssh'
            sh '''
                echo "$SSH_PRIVATE_KEY" > ~/.ssh/jenkins_financeme_key
                chmod 600 ~/.ssh/jenkins_financeme_key
                # Generate public key
                ssh-keygen -y -f ~/.ssh/jenkins_financeme_key > ~/.ssh/jenkins_financeme_key.pub
                '''
            sh 'terraform init'
            sh 'terraform apply -auto-approve -var="environment=test" -var="public_key=$(cat ~/.ssh/jenkins_financeme_key.pub)"'

            // Generate inventory file dynamically
            sh '''
                mkdir -p ../ansible/inventory/
                echo "test-server ansible_host=$(terraform output -raw test_server_ip)" > ../ansible/inventory/test-hosts.yml
                echo "ansible_user=ubuntu" >> ../ansible/inventory/test-hosts.yml
                echo "ansible_ssh_private_key_file=~/.ssh/financeme-key.pem" >> ../ansible/inventory/test-hosts.yml
            '''
                }
             }
        }

        // Stage 5: Deploy to Test Server
        stage('Deploy to Test') {
            steps {
                ansiblePlaybook(
                    playbook: 'ansible/deploy-app.yml',
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
                    // Generate inventory file dynamically
                    sh '''
                      echo "prod-server ansible_host=$(terraform output -raw prod_server_ip)" > ../ansible/inventory/prod-hosts.yml
                      echo "ansible_user=ubuntu" >> ../ansible/inventory/prod-hosts.yml
                      echo "ansible_ssh_private_key_file=~/.ssh/financeme-key.pem" >> ../ansible/inventory/prod-hosts.yml
                  '''
                }
                ansiblePlaybook(
                    playbook: 'ansible/configure-server.yml',
                    inventory: 'ansible/inventory/prod-hosts.yml'
                )
                ansiblePlaybook(
                    playbook: 'ansible/deploy-app.yml',
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
            sh 'rm -f ~/.ssh/jenkins_financeme_key*'
        }
    }
}
