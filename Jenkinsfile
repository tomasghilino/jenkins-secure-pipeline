def nodeImage = 'node:24.21.0-trixie-slim@sha256:8ec5d7557396cfe32d21c3f9c13072355ceab22b584578ca4bb28af31120cffe'

pipeline {
  agent { label 'docker' }

  options {
    skipDefaultCheckout()
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    CI = 'true'
    NO_COLOR = '1'
    npm_config_cache = "${WORKSPACE}/.npm-cache"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.IMAGE_TAG = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
        }
      }
    }

    stage('Node') {
      agent {
        docker {
          image nodeImage
          reuseNode true
        }
      }
      stages {
        stage('Install') {
          steps {
            dir('app') {
              sh 'npm ci --ignore-scripts'
            }
          }
        }

        stage('Lint') {
          steps {
            dir('app') {
              sh 'npm run lint -- --format unix'
              sh 'npm run format:check'
            }
          }
        }

        stage('Typecheck') {
          steps {
            dir('app') {
              sh 'npm run typecheck'
            }
          }
        }

        stage('Unit tests') {
          steps {
            dir('app') {
              sh 'npm test'
            }
          }
        }
      }
    }

    stage('Integration tests') {
      agent {
        docker {
          image nodeImage
          reuseNode true
          // socket of the isolated dind daemon, not the developer machine; 2375 is its docker group
          args '-v /var/run/docker.sock:/var/run/docker.sock --group-add 2375'
        }
      }
      steps {
        dir('app') {
          sh 'env -u DOCKER_HOST -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH npm run test:e2e'
        }
      }
    }

    stage('Docker build') {
      steps {
        sh '''
          docker build \
            --label org.opencontainers.image.revision="$IMAGE_TAG" \
            --label org.opencontainers.image.source=https://github.com/tomasghilino/jenkins-secure-pipeline \
            -t jsp-api:"$IMAGE_TAG" \
            app
        '''
      }
    }
  }

  post {
    cleanup {
      deleteDir()
    }
  }
}
