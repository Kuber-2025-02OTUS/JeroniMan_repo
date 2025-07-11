#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Installing Vault ===${NC}"

# 1. Проверяем, что Consul установлен
echo "Checking Consul installation..."
if ! kubectl get pods -n consul -l app=consul,component=server &>/dev/null; then
    echo -e "${RED}Error: Consul is not installed!${NC}"
    echo "Please run ./01-install-consul.sh first"
    exit 1
fi

# 2. Добавляем Helm репозиторий (если еще не добавлен)
echo "Adding HashiCorp Helm repository..."
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# 3. Клонируем репозиторий Vault для референса
if [ ! -d "vault-helm" ]; then
    echo "Cloning vault-helm repository for reference..."
    git clone https://github.com/hashicorp/vault-helm.git
fi

# 4. Создаем namespace для Vault
echo "Creating vault namespace..."
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -

# 5. Устанавливаем Vault
echo -e "${GREEN}Installing Vault in HA mode with Consul backend...${NC}"

# Команда установки Vault
helm upgrade --install vault hashicorp/vault \
  --namespace vault \
  --values vault-values.yaml \
  --version 0.27.0 \
  --wait \
  --timeout 10m

echo ""
echo "Vault installation command:"
echo "helm upgrade --install vault hashicorp/vault \\"
echo "  --namespace vault \\"
echo "  --values vault-values.yaml \\"
echo "  --version 0.27.0 \\"
echo "  --wait"

# 6. Ждем готовности подов
echo -e "${YELLOW}Waiting for Vault pods to be ready...${NC}"
sleep 30
kubectl get pods -n vault

# 7. Проверяем статус Vault
echo -e "${GREEN}Checking Vault status...${NC}"
for i in 0 1 2; do
    echo "vault-$i status:"
    kubectl exec -n vault vault-$i -- vault status || echo "Vault-$i is sealed or not initialized"
done

echo ""
echo -e "${YELLOW}=== IMPORTANT: Vault needs to be initialized and unsealed ===${NC}"
echo ""
echo "To initialize Vault, run:"
echo "kubectl exec -n vault vault-0 -- vault operator init -key-shares=5 -key-threshold=3"
echo ""
echo "Save the unseal keys and root token securely!"
echo ""
echo "To access Vault UI:"
echo "kubectl port-forward -n vault svc/vault 8200:8200"
echo "Then open: http://localhost:8200"

echo ""
echo -e "${GREEN}=== Vault installation completed! ===${NC}"