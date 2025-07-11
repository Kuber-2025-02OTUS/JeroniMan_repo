#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Creating SecretStore and ExternalSecret ===${NC}"

# 1. Создаем SecretStore
echo "Creating SecretStore..."
kubectl apply -f vault-secretstore.yaml

# 2. Проверяем статус SecretStore
echo -e "${YELLOW}Checking SecretStore status...${NC}"
sleep 5
kubectl get secretstore vault-backend -n vault
kubectl describe secretstore vault-backend -n vault

# Проверяем, что SecretStore готов
echo "Waiting for SecretStore to be ready..."
for i in {1..30}; do
    STATUS=$(kubectl get secretstore vault-backend -n vault -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [ "$STATUS" == "True" ]; then
        echo -e "${GREEN}SecretStore is ready!${NC}"
        break
    fi
    echo "Waiting... (attempt $i/30)"
    sleep 2
done

# 3. Создаем ExternalSecret
echo -e "${GREEN}Creating ExternalSecret...${NC}"
kubectl apply -f external-secret.yaml

# 4. Проверяем статус ExternalSecret
echo -e "${YELLOW}Checking ExternalSecret status...${NC}"
sleep 5
kubectl get externalsecret otus-cred -n vault
kubectl describe externalsecret otus-cred -n vault

# 5. Ждем создания Secret
echo "Waiting for Secret to be created..."
for i in {1..30}; do
    if kubectl get secret otus-cred -n vault &>/dev/null; then
        echo -e "${GREEN}Secret created!${NC}"
        break
    fi
    echo "Waiting... (attempt $i/30)"
    sleep 2
done

# 6. Проверяем содержимое Secret
echo -e "${GREEN}Verifying Secret contents...${NC}"
echo "Secret data:"
kubectl get secret otus-cred -n vault -o jsonpath='{.data}' | jq

echo ""
echo "Decoded values:"
echo -n "username: "
kubectl get secret otus-cred -n vault -o jsonpath='{.data.username}' | base64 -d
echo ""
echo -n "password: "
kubectl get secret otus-cred -n vault -o jsonpath='{.data.password}' | base64 -d
echo ""

echo ""
echo -e "${GREEN}=== External Secrets configuration completed! ===${NC}"