#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Initializing and Unsealing Vault ===${NC}"

# 1. Инициализация Vault
echo "Initializing Vault..."
INIT_OUTPUT=$(kubectl exec -n vault vault-0 -- vault operator init -key-shares=5 -key-threshold=3 -format=json)

# Сохраняем ключи и токен
echo "$INIT_OUTPUT" > vault-init-keys.json
echo -e "${YELLOW}IMPORTANT: Vault keys saved to vault-init-keys.json${NC}"
echo -e "${RED}Keep this file secure and do not commit it to git!${NC}"

# Извлекаем ключи и root token
UNSEAL_KEY_1=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')
UNSEAL_KEY_2=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[1]')
UNSEAL_KEY_3=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[2]')
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')

# 2. Распечатываем все поды Vault
echo -e "${GREEN}Unsealing Vault pods...${NC}"
for i in 0 1 2; do
    echo "Unsealing vault-$i..."
    kubectl exec -n vault vault-$i -- vault operator unseal $UNSEAL_KEY_1
    kubectl exec -n vault vault-$i -- vault operator unseal $UNSEAL_KEY_2
    kubectl exec -n vault vault-$i -- vault operator unseal $UNSEAL_KEY_3
done

# 3. Проверяем статус
echo -e "${GREEN}Checking Vault status...${NC}"
for i in 0 1 2; do
    echo "vault-$i:"
    kubectl exec -n vault vault-$i -- vault status
done

# 4. Логинимся с root token
echo -e "${GREEN}Logging in with root token...${NC}"
kubectl exec -n vault vault-0 -- vault login $ROOT_TOKEN

# 5. Создаем KV секретное хранилище
echo -e "${GREEN}Creating KV secret engine at /otus...${NC}"
kubectl exec -n vault vault-0 -- vault secrets enable -path=otus kv-v2

# 6. Создаем секрет
echo -e "${GREEN}Creating secret at otus/cred...${NC}"
kubectl exec -n vault vault-0 -- vault kv put otus/cred username='otus' password='asajkjkahs'

# 7. Проверяем секрет
echo -e "${GREEN}Verifying secret...${NC}"
kubectl exec -n vault vault-0 -- vault kv get otus/cred

echo ""
echo -e "${GREEN}=== Vault initialization completed! ===${NC}"
echo ""
echo "Root token: $ROOT_TOKEN"
echo "(Also saved in vault-init-keys.json)"
echo ""
echo "To access Vault UI:"
echo "kubectl port-forward -n vault svc/vault 8200:8200"
echo "Use root token to login"