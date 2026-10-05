def nodeImage = 'node:24.21.0-trixie-slim@sha256:8ec5d7557396cfe32d21c3f9c13072355ceab22b584578ca4bb28af31120cffe'
def scannerImage = 'sonarsource/sonar-scanner-cli:12.2.0.4256_8.1.0@sha256:a3f4215076706c95a17a68c19322ee916e40a3acd081a8c1a1e839e0194afa57'
def gitleaksImage = 'ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f'
def terraformImage = 'hashicorp/terraform:1.16.4@sha256:985cdc6c1d9b0a65b83377f666efd2f740b47f02ac55be1ced3d18f7d3b0e829'
def tflintImage = 'ghcr.io/terraform-linters/tflint:v0.64.0@sha256:1c595f42d794c32c45a6ea8b58655fd66433d4ca3b1bc631c574a48d120bd19f'
def checkovImage = 'bridgecrew/checkov:3.3.20@sha256:6d20ebbcde58b2dce6e3151a6771fefa4d468281fe442475455623f5799b9f53'
// trivy releases were hijacked in march 2026, so this digest was pinned only after cosign verified
// it was signed by the aquasecurity/trivy release workflow
def trivyImage = 'ghcr.io/aquasecurity/trivy:0.74.0@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969'
def awsCliImage = 'amazon/aws-cli:2.37.8@sha256:420ab345e847291b541b45d989535f55bcff957c27fa1100fae4aa233e86398c'
// pinned after cosign verified its slsa provenance from the jqlang/jq release workflow
def jqImage = 'ghcr.io/jqlang/jq:1.8.2@sha256:b9c68867e5766576263a222e91db3de422d802069c7af70440e667a95344e486'
// pinned after cosign verified it against the public key published in the curl/curl-container repository
def curlImage = 'curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777'
// zap publishes no signatures or provenance, so the digest of the official 2.17.0 image is the only pin
def zapImage = 'ghcr.io/zaproxy/zaproxy:2.17.0@sha256:781a2bdaea47324e7bab583e2263f21d257b0aee61ed51521a5be45f5f5081ef'

// staging and production deploy the same way, only the names of their ecs resources differ
def deployApi(String environmentName) {
  withEnv(["ECS_CLUSTER=jsp-${environmentName}", 'ECS_SERVICE=api', "TASK_FAMILY=jsp-${environmentName}-api"]) {
    stage('Register revision') {
      // terraform owns everything in the task definition except the image, so jenkins copies the
      // latest revision, drops the fields aws generates and swaps only the image
      sh '''
        $AWS ecs describe-task-definition --task-definition "$TASK_FAMILY" --include TAGS --output json > task-definition.json
        $JQ --arg image "$ECR_IMAGE" '
          .tags as $tags
          | .taskDefinition
          | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
          | .containerDefinitions |= map(if .name == "api" then .image = $image else . end)
          | .tags = ($tags | map(if .key == "ManagedBy" then .value = "jenkins" else . end))
        ' < task-definition.json > task-definition-new.json
      '''
      // the aws cli container cannot see the workspace, so the json goes in as an argument
      env.TASK_DEFINITION = sh(
        script: '$AWS ecs register-task-definition --cli-input-json "$(cat task-definition-new.json)" --query taskDefinition.taskDefinitionArn --output text',
        returnStdout: true
      ).trim()
      echo "registered ${env.TASK_DEFINITION} with ${env.ECR_IMAGE}"
    }

    stage('Migrate database') {
      // a one-off task with the new revision, so the schema is ready before any new api task serves traffic
      sh '''
        network=$($AWS ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --query 'services[0].networkConfiguration' --output json)
        task=$($AWS ecs run-task --cluster "$ECS_CLUSTER" --task-definition "$TASK_DEFINITION" \
          --launch-type FARGATE --started-by jenkins-migrate --propagate-tags TASK_DEFINITION \
          --network-configuration "$network" \
          --overrides '{"containerOverrides":[{"name":"api","command":["node_modules/node-pg-migrate/bin/node-pg-migrate.js","up"]}]}' \
          --query 'tasks[0].taskArn' --output text)
        if [ "$task" = None ]; then
          echo "the migration task did not start" >&2
          exit 1
        fi

        $AWS ecs wait tasks-stopped --cluster "$ECS_CLUSTER" --tasks "$task"
        code=$($AWS ecs describe-tasks --cluster "$ECS_CLUSTER" --tasks "$task" --query 'tasks[0].containers[0].exitCode' --output text)
        if [ "$code" != 0 ]; then
          $AWS ecs describe-tasks --cluster "$ECS_CLUSTER" --tasks "$task" --query 'tasks[0].stoppedReason' --output text >&2
          echo "migrations failed with exit code $code, logs in /ecs/$TASK_FAMILY stream api/api/${task##*/}" >&2
          exit 1
        fi
      '''
    }

    stage('Roll out service') {
      sh '$AWS ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --task-definition "$TASK_DEFINITION" --query service.taskDefinition --output text'
      // returns once the old task is drained and only the new revision runs, or fails after ten minutes
      sh '$AWS ecs wait services-stable --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"'
      sh '''
        running=$($AWS ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --query 'services[0].taskDefinition' --output text)
        if [ "$running" != "$TASK_DEFINITION" ]; then
          echo "the service runs $running instead of $TASK_DEFINITION" >&2
          exit 1
        fi
      '''
    }
  }
}

// /users reads the database, so it also proves the tasks reach rds and the migrations ran
def smokeTest(String environmentName) {
  withEnv(["LOAD_BALANCER=jsp-${environmentName}-alb"]) {
    def url = 'http://' + sh(
      script: '$AWS elbv2 describe-load-balancers --names "$LOAD_BALANCER" --query "LoadBalancers[0].DNSName" --output text',
      returnStdout: true
    ).trim()
    withEnv(["BASE_URL=${url}"]) {
      sh '''
        health=$($CURL "$BASE_URL/health")
        if [ "$health" != '{"status":"ok"}' ]; then
          echo "unexpected /health response: $health" >&2
          exit 1
        fi
        $CURL "$BASE_URL/users" > /dev/null
      '''
    }
    return url
  }
}

pipeline {
  agent { label 'docker' }

  options {
    skipDefaultCheckout()
    disableConcurrentBuilds()
    // a full build plus the 30 minutes the production approval may wait
    timeout(time: 60, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    CI = 'true'
    NO_COLOR = '1'
    npm_config_cache = "${WORKSPACE}/.npm-cache"
    AWS_REGION = 'us-east-1'
    // only the dind network namespace is close enough to imds for the instance role, build containers are not
    AWS = "docker run --rm --network host -e AWS_REGION ${awsCliImage}"
    JQ = "docker run --rm -i --network none ${jqImage}"
    // retries cover the seconds after a rollout while the load balancer settles
    CURL = "docker run --rm ${curlImage} --fail --silent --show-error --max-time 10 --retry 5 --retry-all-errors --retry-delay 3"
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

    stage('Secret scan') {
      agent {
        docker {
          image gitleaksImage
          reuseNode true
          // jenkins keeps the container alive with its own command, so the gitleaks entrypoint is cleared
          args '--entrypoint= --network none'
        }
      }
      steps {
        sh 'gitleaks git --redact --verbose --no-banner --log-opts=HEAD .'
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

        stage('Dependency audit') {
          steps {
            dir('app') {
              // report every advisory, dev tooling included, without failing the build
              sh 'npm audit --audit-level=none'
              // block high and critical advisories in the dependencies that ship in the image
              sh 'npm audit --omit=dev --audit-level=high'
              // every installed package must carry a valid npm registry signature
              sh 'npm audit signatures'
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
              sh 'npm test -- --coverage'
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
          sh 'env -u DOCKER_HOST -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH npm run test:e2e -- --coverage'
        }
      }
    }

    stage('SonarQube') {
      // community build tracks a single branch, so analyses from other branches would overwrite dev
      when {
        branch 'dev'
      }
      stages {
        stage('Analysis') {
          agent {
            docker {
              image scannerImage
              reuseNode true
              // the compose service name sonarqube only resolves through docker's embedded dns in the dind network namespace
              args '--network host --dns 127.0.0.11'
            }
          }
          steps {
            withSonarQubeEnv('sonarqube') {
              sh 'sonar-scanner'
            }
          }
        }

        stage('Quality gate') {
          steps {
            timeout(time: 5, unit: 'MINUTES') {
              waitForQualityGate abortPipeline: true
            }
          }
        }
      }
    }

    stage('Terraform') {
      environment {
        TF_IN_AUTOMATION = 'true'
        TF_INPUT = 'false'
        CHECKPOINT_DISABLE = 'true'
        TF_PLUGIN_CACHE_DIR = "${WORKSPACE}/.terraform-plugins"
      }
      stages {
        stage('Format and validate') {
          agent {
            docker {
              image terraformImage
              reuseNode true
              args '--entrypoint='
            }
          }
          steps {
            sh 'mkdir -p "$TF_PLUGIN_CACHE_DIR"'
            sh 'terraform fmt -check -recursive -diff infra'
            // every stack commits its lock file, so new stacks are picked up without editing this list
            sh '''
              for lock in infra/*/.terraform.lock.hcl infra/environments/*/.terraform.lock.hcl; do
                stack=$(dirname "$lock")
                terraform -chdir="$stack" init -backend=false -lockfile=readonly -no-color
                terraform -chdir="$stack" validate -no-color
              done
            '''
          }
        }

        stage('TFLint') {
          agent {
            docker {
              image tflintImage
              reuseNode true
              args '--entrypoint='
            }
          }
          steps {
            // the container user has no home, and tflint keeps plugins and the sigstore root that verifies them there
            // recursive mode reads .tflint.hcl from each stack folder unless the config path is absolute
            sh '''
              export HOME="$(mktemp -d)"
              tflint --init --config="$WORKSPACE/.tflint.hcl"
              tflint --recursive --chdir=infra --config="$WORKSPACE/.tflint.hcl"
            '''
          }
        }

        stage('Checkov') {
          agent {
            docker {
              image checkovImage
              reuseNode true
              args '--entrypoint= --network none'
            }
          }
          steps {
            // --skip-download keeps checkov from calling the prisma cloud api, so it runs offline
            sh 'checkov -d infra --framework terraform --external-checks-dir checkov --quiet --compact --skip-download'
          }
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
        // scanners read the image from a file, so they never need access to the docker daemon
        sh 'docker save -o jsp-api.tar jsp-api:"$IMAGE_TAG"'
      }
    }

    stage('Trivy') {
      agent {
        docker {
          image trivyImage
          reuseNode true
          args '--entrypoint='
        }
      }
      environment {
        TRIVY_CACHE_DIR = "${WORKSPACE}/.trivy-cache"
        TRIVY_IGNOREFILE = "${WORKSPACE}/.trivyignore"
      }
      stages {
        stage('Filesystem scan') {
          steps {
            // the lock file lists every dependency; installed node_modules would only repeat it
            sh 'trivy fs --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --skip-dirs app/node_modules app'
          }
        }

        stage('Image scan') {
          steps {
            // full report of every severity, including accepted findings, without failing the build
            sh 'trivy image --scanners vuln --show-suppressed --input jsp-api.tar'
            // block high and critical vulnerabilities that already have a fixed version
            sh 'trivy image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --input jsp-api.tar'
            // block any secret baked into an image layer, whatever its severity
            sh 'trivy image --scanners secret --exit-code 1 --input jsp-api.tar'
          }
        }

        stage('SBOM') {
          steps {
            // cyclonedx inventory of every os package and npm library in the image, kept with the build
            // so a future advisory can be checked with trivy sbom without pulling the image again
            sh 'trivy image --format cyclonedx --output jsp-api.cdx.json --input jsp-api.tar'
            archiveArtifacts artifacts: 'jsp-api.cdx.json', fingerprint: true
          }
        }
      }
    }

    stage('Push to ECR') {
      when { branch 'dev' }
      environment {
        // registry credentials live in the workspace and are deleted with it
        DOCKER_CONFIG = "${WORKSPACE}/.docker"
      }
      steps {
        script {
          def account = sh(script: '$AWS sts get-caller-identity --query Account --output text', returnStdout: true).trim()
          env.ECR_IMAGE = "${account}.dkr.ecr.${AWS_REGION}.amazonaws.com/jsp-api:${IMAGE_TAG}"
        }
        sh '''
          if found=$($AWS ecr describe-images --repository-name jsp-api --image-ids imageTag="$IMAGE_TAG" 2>&1); then
            echo "jsp-api:$IMAGE_TAG is already in ecr and tags are immutable, skipping the push"
            exit 0
          fi
          case $found in
            *ImageNotFoundException*) ;;
            *) echo "$found" >&2; exit 1 ;;
          esac

          registry=${ECR_IMAGE%%/*}
          $AWS ecr get-login-password | docker login --username AWS --password-stdin "$registry"
          docker tag jsp-api:"$IMAGE_TAG" "$ECR_IMAGE"
          docker push "$ECR_IMAGE"
          docker logout "$registry"
          docker rmi "$ECR_IMAGE"
        '''
      }
    }

    stage('Deploy staging') {
      when { branch 'dev' }
      steps {
        script {
          deployApi('staging')
        }
      }
    }

    stage('Smoke test') {
      when { branch 'dev' }
      steps {
        script {
          env.STAGING_URL = smokeTest('staging')
        }
      }
    }

    stage('ZAP baseline') {
      when { branch 'dev' }
      environment {
        // zap reads its rule policy from /zap/wrk and writes the reports next to it
        ZAP = "docker run --rm -v ${WORKSPACE}/zap:/zap/wrk:rw ${zapImage}"
      }
      steps {
        // the api has no links to crawl, so the passive scan starts from a real endpoint
        // -silent keeps zap from updating its rules over the internet, so results depend only on the pinned image
        // -I lets WARN rules pass, while any FAIL rule from zap/baseline.conf exits 1 and blocks promotion
        sh '$ZAP zap-baseline.py -t "$STAGING_URL/users" -c baseline.conf -I -z -silent -r zap-report.html -J zap-report.json'
      }
      post {
        always {
          archiveArtifacts artifacts: 'zap/zap-report.*', allowEmptyArchive: true
        }
      }
    }

    stage('Approve production') {
      when {
        // evaluated before the input, so other branches are never asked
        beforeInput true
        branch 'dev'
      }
      options {
        // an unanswered approval aborts the build, so the image is simply not promoted
        timeout(time: 30, unit: 'MINUTES')
      }
      input {
        message 'Deploy this image to production?'
        ok 'Deploy to production'
        submitter 'admin'
        submitterParameter 'APPROVER'
      }
      steps {
        echo "${APPROVER} approved ${ECR_IMAGE} for production"
      }
    }

    stage('Deploy production') {
      when { branch 'dev' }
      steps {
        script {
          // the exact image staging just validated, never rebuilt
          deployApi('production')
        }
      }
    }

    stage('Verify production') {
      when { branch 'dev' }
      steps {
        script {
          smokeTest('production')
        }
      }
    }
  }

  post {
    cleanup {
      deleteDir()
    }
  }
}
