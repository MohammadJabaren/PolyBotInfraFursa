if [ ! -f /etc/kubernetes/admin.conf ]; then
    sudo kubeadm init --pod-network-cidr=192.168.0.0/16

    mkdir -p \$HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config
    sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config

    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/calico.yaml
  else
    echo "✅ Cluster already initialized"
  fi