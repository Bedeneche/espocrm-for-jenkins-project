pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 60, unit: 'MINUTES')
    }

    environment {
        DOCKERHUB_USER = 'bedeneche'          // <-- change
        IMAGE_NAME     = "${DOCKERHUB_USER}/espocrm"
        IMAGE_TAG      = "${env.BUILD_NUMBER}"
        ANSIBLE_CONFIG = "${env.WORKSPACE}/ansible/ansible.cfg"
        ANSIBLE_HOST_KEY_CHECKING = 'False'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker image') {
            steps {
                sh 'docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -t ${IMAGE_NAME}:latest .'
            }
        }

        stage('Smoke test') {
            steps {
                sh '''
                    docker run --rm ${IMAGE_NAME}:${IMAGE_TAG} php -v
                    docker run --rm ${IMAGE_NAME}:${IMAGE_TAG} php -m | grep -i pdo_mysql
                    docker run --rm ${IMAGE_NAME}:${IMAGE_TAG} test -f /var/www/html/index.php
                '''
            }
        }

        stage('Push to Docker Hub') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                                  usernameVariable: 'DH_USER',
                                                  passwordVariable: 'DH_PASS')]) {
                    sh '''
                        echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${IMAGE_NAME}:latest
                    '''
                }
            }
        }

        stage('Deploy with Ansible') {
            steps {
                sh '''
                    cd ansible
                    ansible all -m ping
                    ansible-playbook deploy.yml \
                      -e app_image=${IMAGE_NAME} \
                      -e app_tag=${IMAGE_TAG}
                '''
            }
        }
    }

    post {
        always {
            sh 'docker logout || true'
            sh 'docker image prune -f || true'   // keep the 15 GB disk from filling up
        }
        success { echo "Deployed ${IMAGE_NAME}:${IMAGE_TAG}" }
        failure { echo 'Pipeline failed - check the stage logs above.' }
    }
}
