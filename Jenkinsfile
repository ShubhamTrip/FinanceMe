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
        // Stage 4: Configure Test Server
        stage('Provision Servers') {
            steps {
                withCredentials([file(credentialsId: 'jenkins-ssh-key', variable: 'SSH_KEY_FILE')]) {
                    sh '''
                        # Ensure .ssh directory exists with correct permissions
                        mkdir -p /var/lib/jenkins/.ssh
                        chmod 700 /var/lib/jenkins/.ssh
                        
                        # Copy the key file
                        cp "$SSH_KEY_FILE" /var/lib/jenkins/.ssh/jenkins_financeme_key
                        chmod 600 /var/lib/jenkins/.ssh/jenkins_financeme_key
                        
                        # Generate public key
                        ssh-keygen -y -f /var/lib/jenkins/.ssh/jenkins_financeme_key > /var/lib/jenkins/.ssh/jenkins_financeme_key.pub || {
                            echo "Failed to generate public key. Key content might be malformed."
                            exit 1
                        }
                        chmod 644 /var/lib/jenkins/.ssh/jenkins_financeme_key.pub
                    '''
                    
                    dir('terraform') {
                        sh 'terraform init'
                        sh '''
                            terraform init
                            terraform apply -auto-approve \
                            -var="environment=test" \
                            -var="environment=prod" \
                            -var="public_key=$(cat /var/lib/jenkins/.ssh/jenkins_financeme_key.pub)"
                        '''
                    }

                    script {
                def TEST_IP = sh(script: 'terraform -chdir=terraform output -raw test_server_ip', returnStdout: true).trim()
                def PROD_IP = sh(script: 'terraform -chdir=terraform output -raw prod_server_ip', returnStdout: true).trim() 
                sh """
                    sed -e 's/__TF_TEST_IP__/${TEST_IP}/g' \
                       ansible/inventory/test-hosts.template.yml > \
                       ansible/inventory/test-hosts.yml

                    sed -e 's/__TF_PROD_IP__/${PROD_IP}/g' \
                       ansible/inventory/prod-hosts.template.yml > \
                       ansible/inventory/prod-hosts.yml
                """
            }
                                  }
            }
        }

        // Stage 5: Deploy to Test Server
        stage('Deploy to Test') {
            steps {
                ansiblePlaybook(
                    playbook: 'ansible/app-deploy.yml',
                    inventory: 'ansible/inventory/test-hosts.yml',
                    extraVars: [
                        'docker_image': "shubhamtrip16/account-service:${env.BUILD_ID}"
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
            steps {
                ansiblePlaybook(
                    playbook: 'ansible/app-deploy.yml',
                    inventory: 'ansible/inventory/prod-hosts.yml',
                    extraVars: [
                        'docker_image': "shubhamtrip16/account-service:${env.BUILD_ID}"
                    ]
                )
            }
        }
        stage('Setup Monitoring') {
        steps {
            // Deploy Node Exporters
            ansiblePlaybook(
                playbook: 'ansible/monitoring-setup.yml',
                inventory: 'ansible/inventory/test-hosts.yml'
            )
            
            ansiblePlaybook(
                playbook: 'ansible/monitoring-setup.yml',
                inventory: 'ansible/inventory/prod-hosts.yml'
            )
            
            // Deploy Prometheus (on a separate monitoring server)
            sh '''
                docker rm -f prometheus || true
                docker run -d \
                    -p 9090:9090 \
                    -v ${WORKSPACE}/ansible/prometheus.yml:/etc/prometheus/prometheus.yml \
                    --name prometheus \
                    prom/prometheus
            '''
            
            // Deploy Grafana
            sh '''
                docker run -d \
                    -p 3000:3000 \
                    --name grafana \
                    grafana/grafana
            '''
        }
     }

     stage('Configure Grafana') {
            steps {
                script {
                    // Wait for Grafana to be ready
                    sh 'while ! curl -s http://localhost:3000; do sleep 5; done'
                    
                    // Add Prometheus datasource
                    sh '''
                        curl -X POST "http://admin:admin@localhost:3000/api/datasources" \
                        -H "Content-Type: application/json" \
                        -d '{
                            "name":"Prometheus",
                            "type":"prometheus",
                            "url":"http://prometheus:9090",
                            "access":"proxy"
                        }'
                    '''
                    
                    // Import Node Exporter dashboard (ID 1860)
                    sh '''
                        curl -X POST "http://admin:admin@localhost:3000/api/dashboards/import" \
                        -H "Content-Type: application/json" \
                        -d '{
                            "dashboard": {
                                "id": null,
                                "uid": null,
                                "title": "Node Exporter Metrics",
                                "timezone": "browser",
                                "schemaVersion": 16,
                                "version": 0
                            },
                            "folderId": 0,
                            "overwrite": true,
                            "inputs": [
                                {
                                    "name": "DS_PROMETHEUS",
                                    "type": "datasource",
                                    "pluginId": "prometheus",
                                    "value": "Prometheus"
                                }
                            ]
                        }'
                    '''
                }
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
