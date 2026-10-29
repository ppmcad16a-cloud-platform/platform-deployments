// Deploys ONE service of the MERN shop to GCP -> Azure -> AWS, one cloud
// after another. Each cloud: Helm rolling update (auto-rollback on failure)
// + smoke test. A failure stops the pipeline, so later clouds keep the old,
// working version.

// helm upgrade for one cloud. kubeArgs (fixed text, never user input) tells
// Helm how to reach that cloud's cluster ('' = the cluster Jenkins runs in).
def helmDeploy(String cloud, String kubeArgs) {
  container('helm') {
    sh """
      helm upgrade --install "\$SERVICE" charts/microservice \\
        --namespace mern ${kubeArgs} \\
        -f values/clouds/${cloud}.yaml \\
        -f "values/services/\$SERVICE.yaml" \\
        --set image.tag="\$IMAGE_TAG" \\
        --rollback-on-failure --wait --timeout 8m
      helm history "\$SERVICE" --namespace mern ${kubeArgs} --max 5
    """
  }
}

def smokeTest(String cloud) {
  container('curl') {
    sh "curl -fsS --retry 6 --retry-delay 10 --retry-all-errors https://${cloud}.\${DOMAIN}/api/health"
  }
}

pipeline {
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
              securityContext:
                runAsUser: 1000
            - name: aws
              image: amazon/aws-cli:2.38.1
              command: ["sleep"]
              args: ["infinity"]
              env:
                # The AWS CLI swaps the GKE token in this file for temporary
                # credentials of this role (no keys anywhere).
                - name: AWS_ROLE_ARN
                  value: arn:aws:iam::722867460821:role/jenkins-deployer-from-gke
                - name: AWS_WEB_IDENTITY_TOKEN_FILE
                  value: /var/run/secrets/tokens/aws/token
                - name: AWS_REGION
                  value: ap-south-1
              volumeMounts:
                - name: aws-token
                  mountPath: /var/run/secrets/tokens/aws
                  readOnly: true
            - name: azure
              image: mcr.microsoft.com/azure-cli:2.91.0
              command: ["sleep"]
              args: ["infinity"]
              volumeMounts:
                - name: azure-token
                  mountPath: /var/run/secrets/tokens/azure
                  readOnly: true
          volumes:
            # GKE-signed identity tokens, one per audience, valid 1 hour.
            - name: aws-token
              projected:
                sources:
                  - serviceAccountToken:
                      audience: sts.amazonaws.com
                      expirationSeconds: 3600
                      path: token
            - name: azure-token
              projected:
                sources:
                  - serviceAccountToken:
                      audience: api://AzureADTokenExchange
                      expirationSeconds: 3600
                      path: token
      '''
    }
  }

  parameters {
    choice(name: 'SERVICE',
           choices: ['identity-service', 'catalog-service', 'commerce-service',
                     'notification-service', 'api-gateway-service', 'client-service'],
           description: 'Which service to deploy')
    string(name: 'IMAGE_TAG', defaultValue: '',
           description: 'Image tag already pushed to ALL registries, e.g. main-a6a9d50')
    string(name: 'TARGETS', defaultValue: 'gcp,azure,aws',
           description: 'Clouds to deploy to, in this order (comma-separated)')
  }

  environment {
    DOMAIN                = 'rishavmukhopadhyay.store'
    AZURE_CLIENT_ID       = 'f8820f82-2d12-4b9c-8ca2-e75e3000282f'
    AZURE_TENANT_ID       = '0fd463ca-1b22-4674-bea5-699c2e0ad98b'
    AZURE_SUBSCRIPTION_ID = '9c0602c2-72a4-4432-a192-7abf998e2b60'
  }

  options {
    timeout(time: 60, unit: 'MINUTES')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }

  stages {
    stage('Validate') {
      steps {
        script {
          if (!(params.IMAGE_TAG ==~ /[A-Za-z0-9][A-Za-z0-9._-]{0,127}/)) {
            error("IMAGE_TAG '${params.IMAGE_TAG}' is not a valid image tag")
          }
          if (!(params.TARGETS ==~ /(gcp|azure|aws)(,(gcp|azure|aws))*/)) {
            error("TARGETS '${params.TARGETS}' must be a comma list of gcp, azure, aws")
          }
        }
      }
    }

    // ---------------- GCP (Jenkins' own cluster: in-cluster credentials)
    stage('GCP: deploy') {
      when { expression { params.TARGETS.split(',').contains('gcp') } }
      steps { helmDeploy('gcp', '') }
    }
    stage('GCP: smoke test') {
      when { expression { params.TARGETS.split(',').contains('gcp') } }
      steps { smokeTest('gcp') }
    }

    // ---------------- Azure (GKE token -> Entra managed identity)
    stage('Azure: credentials') {
      when { expression { params.TARGETS.split(',').contains('azure') } }
      steps {
        container('azure') {
          sh '''
            set -e
            mkdir -p .kube
            az login --service-principal --username "$AZURE_CLIENT_ID" --tenant "$AZURE_TENANT_ID" \
              --federated-token "$(cat /var/run/secrets/tokens/azure/token)" \
              --allow-no-subscriptions --output none
            az aks get-credentials --subscription "$AZURE_SUBSCRIPTION_ID" \
              --resource-group rg-prod-cluster --name prod-aks \
              --file .kube/azure.config --overwrite-existing
            grep 'server:' .kube/azure.config | head -1 | awk '{print $2}' > .kube/azure-server
            grep 'certificate-authority-data:' .kube/azure.config | head -1 | awk '{print $2}' | base64 -d > .kube/azure-ca.crt
            # Short-lived Entra token for the AKS API ("6dae42f8-..." = AKS sign-in app)
            az account get-access-token --resource 6dae42f8-4368-4678-94ff-3960e28e3630 \
              --query accessToken -o tsv > .kube/azure-token
          '''
        }
      }
    }
    stage('Azure: deploy') {
      when { expression { params.TARGETS.split(',').contains('azure') } }
      steps {
        helmDeploy('azure', '--kube-apiserver "$(cat .kube/azure-server)" --kube-ca-file .kube/azure-ca.crt --kube-token "$(cat .kube/azure-token)"')
      }
    }
    stage('Azure: smoke test') {
      when { expression { params.TARGETS.split(',').contains('azure') } }
      steps { smokeTest('azure') }
    }

    // ---------------- AWS (GKE token -> IAM role -> EKS access entry)
    stage('AWS: credentials') {
      when { expression { params.TARGETS.split(',').contains('aws') } }
      steps {
        container('aws') {
          sh '''
            set -e
            mkdir -p .kube
            aws sts get-caller-identity
            aws eks describe-cluster --name prod-eks --query cluster.endpoint --output text > .kube/aws-server
            aws eks describe-cluster --name prod-eks --query cluster.certificateAuthority.data --output text | base64 -d > .kube/aws-ca.crt
            aws eks get-token --cluster-name prod-eks --query status.token --output text > .kube/aws-token
          '''
        }
      }
    }
    stage('AWS: deploy') {
      when { expression { params.TARGETS.split(',').contains('aws') } }
      steps {
        helmDeploy('aws', '--kube-apiserver "$(cat .kube/aws-server)" --kube-ca-file .kube/aws-ca.crt --kube-token "$(cat .kube/aws-token)"')
      }
    }
    stage('AWS: smoke test') {
      when { expression { params.TARGETS.split(',').contains('aws') } }
      steps { smokeTest('aws') }
    }
  }

  post {
    always {
      // The short-lived tokens die with the pod anyway; delete them early.
      container('helm') { sh 'rm -rf .kube' }
    }
  }
}
