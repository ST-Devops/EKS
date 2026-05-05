#!/bin/bash

set -e  # Exit on error

########################################
# 📁 Resolve project root path
########################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Script Dir: $SCRIPT_DIR"
echo "Project Root: $PROJECT_ROOT"

########################################
# 🔧 CONFIGURATION (EDIT THESE)
########################################
REGION="ap-south-1"
CLUSTER_NAME="eks-learning"
ACCOUNT_ID="<ACCOUNT_ID>"

KARPENTER_POLICY_NAME="KarpenterFullAccess"
KARPENTER_ROLE_NAME="KarpenterControllerRole"

########################################
# 🚀 STEP 1: Update kubeconfig
########################################
echo "Updating kubeconfig..."
aws eks update-kubeconfig \
  --region ${REGION} \
  --name ${CLUSTER_NAME}

########################################
# 🚀 STEP 2: Install Helm (if not exists)
########################################
if ! command -v helm &> /dev/null
then
  echo "Helm not found. Installing..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "Helm already installed"
fi

########################################
# 🚀 STEP 3: Add Helm repos
########################################
echo "Adding Helm repositories..."
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

########################################
# 🚀 STEP 4: Install Istio
########################################
echo "Installing Istio..."
helm install istio-base istio/base -n istio-system --create-namespace
helm install istiod istio/istiod -n istio-system
helm install istio-ingress istio/gateway -n istio-system

########################################
# 🚀 STEP 5: Install KEDA
########################################
echo "Installing KEDA..."
helm install keda kedacore/keda -n keda --create-namespace

########################################
# 🚀 STEP 6: Enable OIDC Provider
########################################
echo "Associating IAM OIDC provider..."
eksctl utils associate-iam-oidc-provider \
  --region ${REGION} \
  --cluster ${CLUSTER_NAME} \
  --approve



echo "Fetching OIDC provider..."

OIDC_PROVIDER=$(aws eks describe-cluster \
  --name ${CLUSTER_NAME} \
  --region ${REGION} \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed -e "s/^https:\/\///")

echo "OIDC Provider: $OIDC_PROVIDER"

echo "Generating trust.json..."

cat <<EOF > trust.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:karpenter:karpenter"
        }
      }
    }
  ]
}
EOF

echo "trust.json generated successfully"

########################################
# 🚀 STEP 7: Create IAM Policy & Role
########################################
echo "Checking if IAM role exists..."

ROLE_EXISTS=$(aws iam get-role \
  --role-name ${KARPENTER_ROLE_NAME} \
  --query 'Role.RoleName' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$ROLE_EXISTS" == "NOT_FOUND" ]; then
  echo "Creating IAM role..."
  aws iam create-role \
    --role-name ${KARPENTER_ROLE_NAME} \
    --assume-role-policy-document file://trust.json
else
  echo "Role already exists. Updating trust policy..."
  aws iam update-assume-role-policy \
    --role-name ${KARPENTER_ROLE_NAME} \
    --policy-document file://trust.json
fi

########################################
# 🚀 STEP 8: Install CRDs
########################################
echo "Installing Karpenter CRDs and Metrics Server..."
kubectl apply -f https://raw.githubusercontent.com/aws/karpenter/main/pkg/apis/crds/karpenter.sh_nodepools.yaml
kubectl apply -f https://raw.githubusercontent.com/aws/karpenter/main/pkg/apis/crds/karpenter.k8s.aws_ec2nodeclasses.yaml
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

########################################
# 🚀 STEP 9: Install Karpenter
########################################
echo "Installing Karpenter..."

CLUSTER_ENDPOINT=$(aws eks describe-cluster \
  --name ${CLUSTER_NAME} \
  --region ${REGION} \
  --query "cluster.endpoint" \
  --output text)

helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --namespace karpenter \
  --create-namespace \
  --set settings.clusterName=${CLUSTER_NAME} \
  --set settings.clusterEndpoint=${CLUSTER_ENDPOINT} \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::${ACCOUNT_ID}:role/${KARPENTER_ROLE_NAME} \
  --set "controller.env[0].name=AWS_REGION" \
  --set "controller.env[0].value=${REGION}"

########################################
# 🚀 STEP 10: Deploy Istio Manifests
########################################
echo "Applying Istio manifests..."
kubectl apply -f ${PROJECT_ROOT}/manifests/istio/

########################################
# 🚀 STEP 11: Deploy Karpenter NodePool
########################################
echo "Applying Karpenter NodePool..."
kubectl apply -f ${PROJECT_ROOT}/manifests/karpenter/nodepool.yaml

########################################
# 🚀 STEP 12: Enable Istio Injection
########################################
echo "Enabling Istio sidecar injection..."
kubectl label namespace default istio-injection=enabled --overwrite

########################################
# 🚀 STEP 13: Deploy Sample App
########################################
echo "Deploying sample app..."
helm install sample-app ${PROJECT_ROOT}/helm/sample-app

########################################
# 🚀 STEP 14: Deploy KEDA Scaled Objects
########################################
echo "Applying KEDA manifests..."
kubectl apply -f ${PROJECT_ROOT}/manifests/keda/

########################################
# ✅ DONE
########################################
echo "====================================="
echo "🎉 Setup completed successfully!"
echo "====================================="