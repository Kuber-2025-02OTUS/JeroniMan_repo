#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Installing Consul ===${NC}"

# 1. Добавляем Helm репозиторий HashiCorp
echo "Adding HashiCorp Helm repository..."
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# 2. Создаем namespace для Consul
echo "Creating consul namespace..."
kubectl create namespace consul --dry-run=client -o yaml | kubectl apply -f -

# 3. Клонируем репозиторий для референса (опционально)
if [ ! -d "consul-k8s" ]; then
    echo "Cloning consul-k8s repository for reference..."
    git clone https://github.com/hashicorp/consul-k8s.git
fi

# 4. Устанавливаем Consul
echo -e "${GREEN}Installing Consul with 3 replicas...${NC}"

# Команда установки Consul
helm upgrade --install consul hashicorp/consul \
  --namespace consul \
  --values consul-values.yaml \
  --version 1.3.1 \
  --wait \
  --timeout 10m

echo ""
echo "Consul installation command:"
echo "helm upgrade --install consul hashicorp/consul \\"
echo "  --namespace consul \\"
echo "  --values consul-values.yaml \\"
echo "  --version 1.3.1 \\"
echo "  --wait"

# 5. Ждем готовности подов
echo -e "${YELLOW}Waiting for Consul pods to be ready...${NC}"
kubectl wait --for=condition=Ready pods -l app=consul,component=server -n consul --timeout=300s

# 6. Проверяем статус
echo -e "${GREEN}Checking Consul status...${NC}"
kubectl get pods -n consul
echo ""
kubectl exec -n consul consul-server-0 -- consul members

# 7. Получаем адрес UI (если включен)
echo ""
echo -e "${GREEN}Consul UI access:${NC}"
echo "Waiting for LoadBalancer IP..."
kubectl get svc consul-ui -n consul

echo ""
echo "To access Consul UI via port-forward:"
echo "kubectl port-forward -n consul svc/consul-ui 8500:80"
echo "Then open: http://localhost:8500"

echo ""
echo -e "${GREEN}=== Consul installation completed! ===${NC}"