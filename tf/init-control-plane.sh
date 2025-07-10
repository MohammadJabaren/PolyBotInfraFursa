#!/bin/bash
exec > >(tee -a setup.log) 2>&1
set -euxo pipefail

# ----------------------------------------
# 1. Initialize Kubernetes Control Plane
# ----------------------------------------
if [ ! -f /etc/kubernetes/admin.conf ]; then
  echo "🛠 Initializing Kubernetes Cluster"
  sudo kubeadm init --pod-network-cidr=192.168.0.0/16

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
else
  echo "✅ Cluster already initialized"
fi

# ----------------------------------------
# 2. Apply Calico CNI (only if not applied)
# ----------------------------------------
if ! kubectl get pods -n kube-system | grep -q calico; then
  echo "🚀 Installing Calico CNI"
  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/calico.yaml
else
  echo "✅ Calico already installed"
fi

# ----------------------------------------
# 3. Create Namespaces
# ----------------------------------------
namespaces=("dev" "prod" "platform")
for ns in "${namespaces[@]}"; do
  if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
    echo "🔧 Creating namespace: $ns"
    kubectl create namespace "$ns"
  else
    echo "✅ Namespace $ns already exists."
  fi
done

# ----------------------------------------
# 4. Create Dev Secrets
# ----------------------------------------
if ! kubectl get secret my-secrets-dev -n dev >/dev/null 2>&1; then
  kubectl create secret generic my-secrets-dev \
    -n dev \
    --from-literal=TELEGRAM_TOKEN="$TELEGRAM_TOKEN" \
    --from-literal=AWS_S3_BUCKET="$AWS_S3_BUCKET" \
    --from-literal=SQS_URL="$SQS_URL" \
    --from-literal=TYPE_ENV="$TYPE_ENV" \
    --from-literal=STRORAGE_TYPE="$STRORAGE_TYPE" \
    --from-literal=PREDICTION_SESSIONS="$PREDICTION_SESSIONS" \
    --from-literal=DETECTION_OBJECTS="$DETECTION_OBJECTS"
else
  echo "✅ Dev secret already exists"
fi

# ----------------------------------------
# 5. Helm Installation (if not present)
# ----------------------------------------
if ! command -v helm &>/dev/null; then
  echo "📦 Installing Helm..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "🧪 Helm version:"
helm version

# ----------------------------------------
# 6. Helm Repos
# ----------------------------------------
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true
helm repo add argo https://argoproj.github.io/argo-helm || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update

# ----------------------------------------
# 7. ArgoCD Installation
# ----------------------------------------
if ! helm list -n platform | grep -q argocd; then
  echo "🚀 Installing ArgoCD"
  helm install argocd argo/argo-cd --namespace platform
else
  echo "✅ ArgoCD already installed"
fi

# ----------------------------------------
# 8. Ingress NGINX (NodePort)
# ----------------------------------------
if ! helm list -n platform | grep -q ingress-nginx; then
  echo "🚀 Installing Ingress NGINX"
  helm install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace platform \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.http=31080 \
    --set controller.service.nodePorts.https=30001
else
  echo "✅ Ingress NGINX already installed"
fi

# ----------------------------------------
# 9. Prometheus + Grafana
# ----------------------------------------
if ! helm list -n platform | grep -q monitoring-stack; then
  echo "📊 Installing Prometheus & Grafana"
  helm install monitoring-stack prometheus-community/kube-prometheus-stack \
    --namespace platform \
    --set grafana.enabled=true \
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
else
  echo "✅ Monitoring stack already installed"
fi

echo "🎉 Setup complete!"
