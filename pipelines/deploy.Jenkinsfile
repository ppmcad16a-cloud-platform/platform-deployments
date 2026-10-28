// Deploys ONE service of the MERN shop with Helm.
// 7b-1: GCP only. 7b-2 adds Azure and AWS, one cloud after another.
pipeline {
  // Every build runs in a fresh, throw-away pod in the "jenkins" namespace,
  // as the Kubernetes service account "jenkins-deployer" (rights: namespace mern only).
  agent {
    kubernetes {
      yaml '''
        apiVersion: v1
        kind: Pod
        spec:
          serviceAccountName: jenkins-deployer
          containers:
            - name: helm
              image: alpine/helm:4.3.0
              command: ["sleep"]
              args: ["infinity"]
            - name: curl
              image: curlimages/curl:8.22.0
              command: ["sleep"]
              args: ["infinity"]
      '''
    }
  }

  parameters {
    choice(name: 'SERVICE',
           choices: ['identity-service', 'catalog-service', 'commerce-service',
                     'notification-service', 'api-gateway-service', 'client-service'],
           description: 'Which service to deploy')
    string(name: 'IMAGE_TAG', defaultValue: '',
           description: 'Image tag already pushed to the registries, e.g. main-a6a9d50')
  }

  options {
    timeout(time: 30, unit: 'MINUTES')
    disableConcurrentBuilds()                      // never two deployments at once
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }

  stages {
    stage('Validate') {
      steps {
        script {
          // Only plain image-tag characters - nothing that could be
          // abused inside the shell commands below.
          if (!(params.IMAGE_TAG ==~ /[A-Za-z0-9][A-Za-z0-9._-]{0,127}/)) {
            error("IMAGE_TAG '${params.IMAGE_TAG}' is not a valid image tag")
          }
        }
      }
    }

    stage('Deploy to GCP') {
      steps {
        container('helm') {
          // Rolling update. --wait: only succeed when the new pods are READY.
          // --rollback-on-failure: otherwise put the previous version back.
          sh '''
            helm upgrade --install "$SERVICE" charts/microservice \
              --namespace mern \
              -f values/clouds/gcp.yaml \
              -f "values/services/$SERVICE.yaml" \
              --set image.tag="$IMAGE_TAG" \
              --rollback-on-failure --wait --timeout 8m
            helm history "$SERVICE" --namespace mern --max 5
          '''
        }
      }
    }

    stage('Smoke test GCP') {
      steps {
        container('curl') {
          // Through Cloudflare, exactly like a real visitor. Fails the build
          // if the shop is not healthy after the deployment.
          sh 'curl -fsS --retry 6 --retry-delay 10 --retry-all-errors https://gcp.rishavmukhopadhyay.store/api/health'
        }
      }
    }
  }
}
