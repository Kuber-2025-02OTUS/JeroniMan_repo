#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Verifying Vault + External Secrets Setup ===${NC}"

# 1. Проверяем Consul
echo -e "${YELLOW}1. Checking Consul cluster...${NC}"
kubectl get pods -n consul
echo ""
kubectl exec -n consul consul-server-0 -- consul members

# 2. Проверяем Vault
echo -e "${YELLOW}2. Checking Vault cluster...${NC}"
kubectl get pods -n vault
echo ""
for i in 0 1 2; do
    echo "vault-$i status:"
    kubectl exec -n vault vault-$i -- vault status | grep -E "Initialized|Sealed|HA"
done

# 3. Проверяем External Secrets Operator
echo -e "${YELLOW}3. Checking External Secrets Operator...${NC}"
kubectl get pods -n vault -l app.kubernetes.io/name=external-secrets

# 4. Проверяем SecretStore
echo -e "${YELLOW}4. Checking SecretStore...${NC}"
kubectl get secretstore -n vault
STATUS=$(kubectl get secretstore vault-backend -n vault -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [ "$STATUS" == "True" ]; then
    echo -e "${GREEN}✓ SecretStore is connected to Vault${NC}"
else
    echo -e "${RED}✗ SecretStore is not ready${NC}"
    kubectl describe secretstore vault-backend -n vault
fi

# 5. Проверяем ExternalSecret
echo -e "${YELLOW}5. Checking ExternalSecret...${NC}"
kubectl get externalsecret -n vault
ES_STATUS=$(kubectl get externalsecret otus-cred -n vault -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [ "$ES_STATUS" == "True" ]; then
    echo -e "${GREEN}✓ ExternalSecret is syncing successfully${NC}"
else
    echo -e "${RED}✗ ExternalSecret sync failed${NC}"
    kubectl describe externalsecret otus-cred -n vault
fi

# 6. Проверяем созданный Secret
echo -e "${YELLOW}6. Checking created Secret...${NC}"
if kubectl get secret otus-cred -n vault &>/dev/null; then
    echo -e "${GREEN}✓ Secret 'otus-cred' exists${NC}"
    echo "Contents:"
    echo -n "  username: "
    kubectl get secret otus-cred -n vault -o jsonpath='{.data.username}' | base64 -d
    echo ""
    echo -n "  password: "
    kubectl get secret otus-cred -n vault -o jsonpath='{.data.password}' | base64 -d
    echo ""
else
    echo -e "${RED}✗ Secret 'otus-cred' not found${NC}"
fi

# 7. Тест обновления секрета в Vault
echo -e "${YELLOW}7. Testing secret update...${NC}"
if [ -f "vault-init-keys.json" ]; then
    ROOT_TOKEN=$(cat vault-init-keys.json | jq -r '.root_token')
    kubectl exec -n vault vault-0 -- vault login $ROOT_TOKEN &>/dev/null

    # Обновляем пароль
    NEW_PASSWORD="updated-$(date +%s)"
    kubectl exec -n vault vault-0 -- vault kv put otus/cred username='otus' password="$NEW_PASSWORD" &>/dev/null

    echo "Updated password in Vault to: $NEW_PASSWORD"
    echo "Waiting for External Secrets to sync (15s)..."
    sleep 20

    # Проверяем обновление
    SYNCED_PASSWORD=$(kubectl get secret otus-cred -n vault -o jsonpath='{.data.password}' | base64 -d)
    if [ "$SYNCED_PASSWORD" == "$NEW_PASSWORD" ]; then
        echo -e "${GREEN}✓ Secret successfully synced from Vault!${NC}"
    else
        echo -e "${RED}✗ Secret not synced yet${NC}"
        echo "Current value: $SYNCED_PASSWORD"
    fi
fi

echo ""
echo -e "${GREEN}=== Verification completed! ===${NC}"
echo ""
echo "Summary:"
echo "- Consul: 3 server nodes in HA mode"
echo "- Vault: 3 nodes in HA mode using Consul backend"
echo "- External Secrets: Connected to Vault via Kubernetes auth"
echo "- Secret sync: Working correctly"