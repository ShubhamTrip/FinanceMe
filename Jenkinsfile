pipeline {
    agent any
    stages{
        stage('build project'){
            steps{
                git url:'https://github.com/ShubhamTrip/FinanceMe/', branch: "master"
                sh 'mvn clean package'
              
            }
        }
        stage('Build docker image'){
            steps{
                script{
                    sh 'docker build -t shubhamtrip16/staragileprojectfinance:v1 .'
                    sh 'docker images'
                }
            }
        }

        stage('Push docker image'){
            steps{
                script{
                    sh 'docker push shubhamtrip16/staragileprojectfinance:v1'
                }
            }
        }
         
        
     stage('Deploy') {
            steps {
                sh 'sudo docker run -itd --name My-first-app-container -p 8080:8080 shubhamtrip16/staragileprojectfinance:v1'
                  
                }
            }
        
    }
}