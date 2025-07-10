#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Deploying Loki Stack with Raw Manifests ===${NC}"
echo -e "${YELLOW}Note: This method uses raw Kubernetes manifests from manifests/ directory${NC}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Загружаем переменные для S3
export AWS_ACCESS_KEY_ID=$(cat $BASE_DIR/outputs/loki-s3-key.json | jq -r .access_key.key_id)
export AWS_SECRET_ACCESS_KEY=$(cat $BASE_DIR/outputs/loki-s3-key.json | jq -r .secret)
export BUCKET_NAME=$(cat $BASE_DIR/outputs/bucket-name.txt)

echo "Using S3 bucket: $BUCKET_NAME"

# 1. Создаем namespace
echo "Creating namespace..."
kubectl apply -f $BASE_DIR/manifests/namespace.yaml

# 2. Деплоим Loki
echo -e "${GREEN}Deploying Loki...${NC}"

# ConfigMap с подстановкой переменных
envsubst < $BASE_DIR/manifests/loki/configmap.yaml | kubectl apply -f -

# Deployment (уже обновлен для использования публичных образов)
kubectl apply -f $BASE_DIR/manifests/loki/deployment.yaml

# Service
kubectl apply -f $BASE_DIR/manifests/loki/service.yaml

# 3. Ждем готовности Loki
echo -e "${YELLOW}Waiting for Loki to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/loki -n loki-stack

# 4. Деплоим Promtail
echo -e "${GREEN}Deploying Promtail...${NC}"

# RBAC
kubectl apply -f $BASE_DIR/manifests/promtail/rbac.yaml

# ConfigMap
kubectl apply -f $BASE_DIR/manifests/promtail/configmap.yaml

# DaemonSet
kubectl apply -f $BASE_DIR/manifests/promtail/daemonset.yaml

# 5. Ждем готовности Promtail
echo -e "${YELLOW}Waiting for Promtail to be ready...${NC}"
kubectl rollout status daemonset/promtail -n loki-stack --timeout=300s

# 6. Проверяем статус
echo -e "${GREEN}Checking deployment status...${NC}"
kubectl get all -n loki-stack

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo "Loki endpoint:"
echo "  kubectl port-forward -n loki-stack svc/loki 3100:3100"
echo ""
echo "Check logs:"
echo "  kubectl logs -n loki-stack -l app=loki"
echo "  kubectl logs -n loki-stack -l app=promtail --prefix=true"