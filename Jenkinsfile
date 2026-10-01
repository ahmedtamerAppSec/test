// Pipeline job for the main branch:
//   build -> secret scan + SCA + Dockerfile lint -> build image -> scan image
//   -> verify -> push to Docker Hub -> deploy the pushed image (by digest).
// Runs on the built-in node (label 'linux') as the 'jenkins' user, with rootless
// Podman. One-time server prerequisites are created by deploy/setup-server.sh.

pipeline {
  agent { label 'linux' }

  options {
    timestamps()
    disableConcurrentBuilds()          // the Trivy DB cache in /var/lib/trivy is shared
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 30, unit: 'MINUTES')
  }

  triggers {
    // gitlab.com cannot reach this server for webhooks, so poll for new commits.
    pollSCM('* * * * *')
  }

  environment {
    DEPLOY_DIR      = '/opt/local-tasks'
    TRIVY_CACHE_DIR = '/var/lib/trivy'
    LOCAL_IMAGE     = "localhost/local-tasks:build-${env.BUILD_NUMBER}"
  }

  stages {
    stage('Build') {
      steps {
        sh 'npm ci --ignore-scripts'
        sh 'npm run build'
      }
    }

    stage('Security scans') {
      parallel {
        stage('Secret scan (TruffleHog)') {
          steps {
            // Full git history is scanned. Unverified findings fail the build too.
            // The raw report contains the secrets themselves, so only a redacted copy is kept.
            sh '''
              set +e
              trufflehog git file://. --config trufflehog-custom.yaml --fail --no-update --json > trufflehog-raw.json
              rc=$?
              set -e
              node scripts/trufflehog-summary.js trufflehog-raw.json trufflehog-report.json
              rm -f trufflehog-raw.json
              exit $rc
            '''
          }
        }

        stage('SCA (Trivy)') {
          steps {
            sh '''
              set +e
              trivy fs --scanners vuln \
                --cache-dir "$TRIVY_CACHE_DIR" \
                --skip-dirs node_modules,build-output \
                --severity HIGH,CRITICAL \
                --exit-code 1 \
                --format json --output trivy-report.json .
              rc=$?
              set -e
              if [ -f trivy-report.json ]; then
                trivy convert --scanners vuln --format table trivy-report.json
              fi
              exit $rc
            '''
          }
        }

        stage('Dockerfile lint (hadolint)') {
          steps {
            sh 'hadolint --failure-threshold warning Dockerfile'
          }
        }
      }
    }

    stage('Build image') {
      steps {
        sh 'podman build --pull=missing --tag "$LOCAL_IMAGE" .'
      }
    }

    stage('Scan image (Trivy)') {
      steps {
        sh '''
          rm -f image.tar
          podman save --format oci-archive --output image.tar "$LOCAL_IMAGE"
          set +e
          trivy image --input image.tar --scanners vuln \
            --cache-dir "$TRIVY_CACHE_DIR" \
            --severity HIGH,CRITICAL \
            --exit-code 1 \
            --format json --output trivy-image-report.json
          rc=$?
          set -e
          rm -f image.tar
          if [ -f trivy-image-report.json ]; then
            trivy convert --scanners vuln --format table trivy-image-report.json
          fi
          exit $rc
        '''
      }
    }

    stage('Verify') {
      steps {
        sh 'node --check app.js'
        // The image starts, runs as a non-root user and contains the app and its dependencies.
        sh '''
          podman run --rm --network none "$LOCAL_IMAGE" \
            node -e "require('pg'); require('fs').accessSync('app.js'); require('fs').accessSync('public/index.html'); if (process.getuid() === 0) process.exit(1)"
        '''
      }
    }

    stage('Push to Docker Hub') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_TOKEN')]) {
          sh '''
            remote="docker.io/$DOCKERHUB_USER/local-tasks"
            commit=$(git rev-parse HEAD)
            printf '%s' "$DOCKERHUB_TOKEN" | podman login docker.io --username "$DOCKERHUB_USER" --password-stdin
            podman push --digestfile image.digest "$LOCAL_IMAGE" "$remote:$commit"
            podman push "$LOCAL_IMAGE" "$remote:latest"
            podman logout docker.io
            # Deploy exactly the image that was scanned: reference it by digest.
            printf '%s@%s\n' "$remote" "$(cat image.digest)" > image.ref
            echo "Pushed $(cat image.ref)"
          '''
        }
      }
    }

    stage('Deploy') {
      steps {
        sh '''
          # Static files for nginx come from the same image.
          rm -rf image-public
          cid=$(podman create "$LOCAL_IMAGE")
          podman cp "$cid:/app/public" image-public
          podman rm "$cid"
          rsync -a --delete image-public/ "$DEPLOY_DIR/public/"
          rm -rf image-public

          # local-tasks.service runs the image named here (it only accepts our repo, by digest).
          if [ -f "$DEPLOY_DIR/image.env" ]; then cp "$DEPLOY_DIR/image.env" "$DEPLOY_DIR/image.env.previous"; fi
          printf 'IMAGE=%s\n' "$(cat image.ref)" > "$DEPLOY_DIR/image.env"

          # Files from the pre-container deployment are no longer used.
          find "$DEPLOY_DIR" -mindepth 1 -maxdepth 1 ! -name public ! -name 'image.env*' -exec rm -rf {} +
        '''
        // Only these three commands are allowed by /etc/sudoers.d/jenkins-deploy.
        sh 'sudo -n /usr/bin/systemctl restart local-tasks'
        sh 'sudo -n /usr/sbin/nginx -t'
        sh 'sudo -n /usr/bin/systemctl reload nginx'
        sh 'curl -fsS --retry 15 --retry-delay 2 --retry-connrefused http://127.0.0.1/health'
        sh 'curl -fsS -o /dev/null http://127.0.0.1/'
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'trufflehog-report.json,trivy-report.json,trivy-image-report.json,image.ref', allowEmptyArchive: true
      // Keep the cached base image, drop this build's app image.
      sh 'rm -f image.tar; podman rmi --ignore "$LOCAL_IMAGE" >/dev/null 2>&1 || true; podman image prune -f >/dev/null 2>&1 || true'
    }
  }
}
