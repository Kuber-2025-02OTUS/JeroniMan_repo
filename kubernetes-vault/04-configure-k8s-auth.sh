#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Configuring Kubernetes Authentication in Vault ===${NC}"

# 1. Создаем ServiceAccount
echo "Creating ServiceAccount and ClusterRoleBinding..."
kubectl apply -f vault-auth-serviceaccount.yaml

# 2. Получаем данные ServiceAccount
echo "Getting ServiceAccount token and certificate..."

# Для Kubernetes 1.24+ нужно создать токен явно
SA_TOKEN=$(kubectl create token vault-auth -n vault --duration=8760h)
# Получаем CA сертификат
SA_CA_CRT=$(kubectl get secret -n vault -o jsonpath="{.items[?(@.metadata.annotations['kubernetes\.io/service-account\.name']=='vault-auth')].data['ca\.crt']}" | base64 -d)
if [ -z "$SA_CA_CRT" ]; then
    # Альтернативный способ получения CA
    SA_CA_CRT=$(kubectl get configmap -n kube-system kube-root-ca.crt -o jsonpath="{.data['ca\.crt']}")
fi

# Получаем адрес API сервера
K8S_HOST=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.server}')

# 3. Получаем root token из сохраненного файла
if [ ! -f "vault-init-keys.json" ]; then
    echo -e "${RED}Error: vault-init-keys.json not found!${NC}"
    echo "Please run ./03-init-vault.sh first"
    exit 1
fi
ROOT_TOKEN=$(cat vault-init-keys.json | jq -r '.root_token')

# 4. Включаем Kubernetes auth метод
echo -e "${GREEN}Enabling Kubernetes auth method...${NC}"
kubectl exec -n vault vault-0 -- vault login $ROOT_TOKEN
kubectl exec -n vault vault-0 -- vault auth enable kubernetes || echo "Kubernetes auth already enabled"

# 5. Конфигурируем Kubernetes auth
echo -e "${GREEN}Configuring Kubernetes auth...${NC}"
kubectl exec -n vault vault-0 -- sh -c "
vault write auth/kubernetes/config \
    token_reviewer_jwt='$SA_TOKEN' \
    kubernetes_host='$K8S_HOST' \
    kubernetes_ca_cert='$SA_CA_CRT' \
    issuer='https://kubernetes.default.svc.cluster.local'
"

# 6. Создаем политику
echo -e "${GREEN}Creating otus-policy...${NC}"
kubectl cp otus-policy.hcl vault/vault-0:/tmp/otus-policy.hcl
kubectl exec -n vault vault-0 -- vault policy write otus-policy /tmp/otus-policy.hcl

# 7. Создаем роль
echo -e "${GREEN}Creating Kubernetes auth role...${NC}"
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/otus \
    bound_service_account_names=vault-auth \
    bound_service_account_namespaces=vault \
    policies=otus-policy \
    ttl=24h

# 8. Проверяем конфигурацию
echo -e "${GREEN}Verifying configuration...${NC}"
echo "Kubernetes auth config:"
kubectl exec -n vault vault-0 -- vault read auth/kubernetes/config

echo ""
echo "Otus role:"
kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/otus

echo ""
echo -e "${GREEN}=== Kubernetes authentication configured! ===${NC}"