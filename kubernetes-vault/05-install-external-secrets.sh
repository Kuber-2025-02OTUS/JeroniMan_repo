#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Installing External Secrets Operator ===${NC}"

# 1. Добавляем Helm репозиторий
echo "Adding External Secrets Helm repository..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# 2. Устанавливаем External Secrets Operator
echo -e "${GREEN}Installing External Secrets Operator in vault namespace...${NC}"

# Команда установки ESO
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace vault \
  --values external-secrets-values.yaml \
  --version 0.9.11 \
  --wait

echo ""
echo "External Secrets Operator installation command:"
echo "helm upgrade --install external-secrets external-secrets/external-secrets \\"
echo "  --namespace vault \\"
echo "  --values external-secrets-values.yaml \\"
echo "  --version 0.9.11 \\"
echo "  --wait"

# 3. Проверяем установку
echo -e "${YELLOW}Checking External Secrets Operator pods...${NC}"
kubectl get pods -n vault -l app.kubernetes.io/name=external-secrets

# 4. Проверяем CRDs
echo -e "${GREEN}Checking installed CRDs...${NC}"
kubectl get crd | grep external-secrets

echo ""
echo -e "${GREEN}=== External Secrets Operator installed! ===${NC}"