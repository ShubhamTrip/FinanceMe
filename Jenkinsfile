pipeline {
    agent any
    environment {
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-key')
        DOCKER_HUB_CREDENTIALS = credentials('docker-hub')
    }
    stages {
        // Stage 1: Checkout Code
        stage('Cloning Repo') {
            steps {
                git branch: 'master', url: 'https://github.com/financeme/account-service.git'
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
                    docker.withRegistry('https://registry.hub.docker.com', 'docker-hub') {
                        docker.image("financeme/account-service:${env.BUILD_ID}").push()
                    }
                }
            }
        }

        // Stage 4: Provision Test Server (Terraform)
        stage('Provision Test Server') {
            steps {
                dir('terraform') {
                    sh 'terraform init'
                    sh 'terraform apply -auto-approve -var="environment=test"'
                }
            }
        }

        // Stage 5: Configure Test Server (Ansible)
        stage('Configure Test Server') {
            steps {
                ansiblePlaybook(
                    playbook: 'ansible/configure-server.yml',
                    inventory: 'ansible/inventory/test-hosts.yml',
                    credentialsId: 'ssh-key'
                )
            }
        }

        // Stage 6: Deploy to Test Server
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

        // Stage 7: Run Automated Tests (Selenium)
        stage('UI Tests') {
            steps {
                sh 'mvn test -Pselenium-tests'  // Runs Selenium tests
            }
        }

        // Stage 8: Deploy to Prod (If Tests Pass)
        stage('Deploy to Prod') {
            when {
                expression { currentBuild.resultIsBetterOrEqualTo('SUCCESS') }
            }
            steps {
                dir('terraform') {
                    sh 'terraform apply -auto-approve -var="environment=prod"'
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
}