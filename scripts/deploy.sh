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
ACCOUNT_ID="$AWS_ACCOUNT_ID"

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

########################################
# 🔧 KARPENTER CONFIG
########################################
KARPENTER_CONTROLLER_ROLE="KarpenterControllerRole-${CLUSTER_NAME}"
KARPENTER_NODE_ROLE="KarpenterNodeRole-${CLUSTER_NAME}"
KARPENTER_POLICY_NAME="KarpenterControllerPolicy-${CLUSTER_NAME}"
KARPENTER_INSTANCE_PROFILE="KarpenterNodeInstanceProfile-${CLUSTER_NAME}"

########################################
# 🚀 STEP 7: Create IAM Trust Policy
########################################
echo "Generating trust policy..."

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
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:karpenter:karpenter",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

########################################
# 🚀 STEP 8: Create Controller IAM Role
########################################
echo "Creating Controller IAM Role..."

aws iam create-role \
  --role-name ${KARPENTER_CONTROLLER_ROLE} \
  --assume-role-policy-document file://trust.json \
  || true

########################################
# 🚀 STEP 9: Create Controller Policy
########################################
cat <<EOF > karpenter-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "KarpenterControllerPermissions",
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeImages",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeSpotPriceHistory",
        "ec2:RunInstances",
        "ec2:CreateFleet",
        "ec2:TerminateInstances",
        "ec2:CreateTags",
        "iam:PassRole",
        "ssm:GetParameter"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name ${KARPENTER_POLICY_NAME} \
  --policy-document file://karpenter-policy.json \
  || true

aws iam attach-role-policy \
  --role-name ${KARPENTER_CONTROLLER_ROLE} \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${KARPENTER_POLICY_NAME}

########################################
# 🚀 STEP 10: Create Node Role
########################################
cat <<EOF > node-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name ${KARPENTER_NODE_ROLE} \
  --assume-role-policy-document file://node-trust-policy.json \
  || true

########################################
# 🚀 STEP 11: Attach Node Policies
########################################
aws iam attach-role-policy \
  --role-name ${KARPENTER_NODE_ROLE} \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-role-policy \
  --role-name ${KARPENTER_NODE_ROLE} \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

aws iam attach-role-policy \
  --role-name ${KARPENTER_NODE_ROLE} \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam attach-role-policy \
  --role-name ${KARPENTER_NODE_ROLE} \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

########################################
# 🚀 STEP 12: Create Instance Profile
########################################
aws iam create-instance-profile \
  --instance-profile-name ${KARPENTER_INSTANCE_PROFILE} \
  || true

aws iam add-role-to-instance-profile \
  --instance-profile-name ${KARPENTER_INSTANCE_PROFILE} \
  --role-name ${KARPENTER_NODE_ROLE} \
  || true

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

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --namespace karpenter \
  --create-namespace \
  --set settings.clusterName=${CLUSTER_NAME} \
  --set settings.clusterEndpoint=${CLUSTER_ENDPOINT} \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::${ACCOUNT_ID}:role/${KARPENTER_CONTROLLER_ROLE} \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
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
kubectl apply -f ${PROJECT_ROOT}/manifests/karpenter/ec2nodeclass.yaml

########################################
# 🚀 STEP 12: Enable Istio Injection
########################################
#echo "Enabling Istio sidecar injection..."
#kubectl label namespace default istio-injection=enabled --overwrite

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


### for cleanup, you can run the following commands to uninstall the applications and delete namespaces:
#helm uninstall istio-ingress -n istio-system || true
#helm uninstall istiod -n istio-system || true
#helm uninstall istio-base -n istio-system || true
#kubectl delete namespace istio-system --ignore-not-found
#helm uninstall keda -n keda || true
#kubectl delete namespace keda --ignore-not-found
#helm uninstall karpenter -n karpenter || true
#kubectl delete namespace karpenter --ignore-not-found
#helm uninstall sample-app