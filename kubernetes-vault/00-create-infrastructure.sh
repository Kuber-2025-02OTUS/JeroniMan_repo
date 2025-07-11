#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Creating Kubernetes Infrastructure for Vault in Yandex Cloud ===${NC}"

# Проверка переменных окружения
echo -e "${YELLOW}Checking environment variables...${NC}"
required_vars=("YC_CLOUD_ID" "YC_FOLDER_ID" "YC_ZONE")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}Error: $var is not set${NC}"
        echo "Please set required environment variables:"
        echo "export YC_CLOUD_ID=<your-cloud-id>"
        echo "export YC_FOLDER_ID=<your-folder-id>"
        echo "export YC_ZONE=ru-central1-a"
        exit 1
    fi
done

# Константы
CLUSTER_NAME="k8s-vault-cluster"
NETWORK_NAME="k8s-vault-network"
SUBNET_NAME="k8s-vault-subnet"
SUBNET_RANGE="10.0.3.0/24"
SA_NAME="k8s-vault-sa"

# 1. Создание сервисного аккаунта
echo -e "${GREEN}1. Creating service account...${NC}"
if ! yc iam service-account get --name $SA_NAME &>/dev/null; then
    yc iam service-account create --name $SA_NAME \
      --description "Service account for Vault Kubernetes cluster"
fi

SA_ID=$(yc iam service-account get --name $SA_NAME --format json | jq -r .id)
echo "Service account ID: $SA_ID"

# Назначаем роли
for role in "editor" "container-registry.images.puller" "vpc.publicAdmin"; do
    yc resource-manager folder add-access-binding \
      --id $YC_FOLDER_ID \
      --role $role \
      --service-account-id $SA_ID 2>/dev/null || true
done

# 2. Создание сети
echo -e "${GREEN}2. Creating network...${NC}"
if ! yc vpc network get --name $NETWORK_NAME &>/dev/null; then
    yc vpc network create --name $NETWORK_NAME
fi
NETWORK_ID=$(yc vpc network get --name $NETWORK_NAME --format json | jq -r .id)

# 3. Создание подсети
echo -e "${GREEN}3. Creating subnet...${NC}"
if ! yc vpc subnet get --name $SUBNET_NAME &>/dev/null; then
    yc vpc subnet create \
      --name $SUBNET_NAME \
      --zone $YC_ZONE \
      --network-id $NETWORK_ID \
      --range $SUBNET_RANGE
fi
SUBNET_ID=$(yc vpc subnet get --name $SUBNET_NAME --format json | jq -r .id)

# 4. Создание кластера
echo -e "${GREEN}4. Creating Kubernetes cluster...${NC}"
if ! yc managed-kubernetes cluster get --name $CLUSTER_NAME &>/dev/null; then
    echo "Creating cluster (this will take 5-10 minutes)..."
    yc managed-kubernetes cluster create \
      --name $CLUSTER_NAME \
      --network-id $NETWORK_ID \
      --master-location zone=$YC_ZONE,subnet-id=$SUBNET_ID \
      --public-ip \
      --service-account-id $SA_ID \
      --node-service-account-id $SA_ID \
      --release-channel regular \
      --master-version 1.28
fi

CLUSTER_ID=$(yc managed-kubernetes cluster get --name $CLUSTER_NAME --format json | jq -r .id)
echo "Cluster ID: $CLUSTER_ID"

# Ждем готовности кластера
echo -e "${YELLOW}Waiting for cluster to be RUNNING...${NC}"
while true; do
    STATUS=$(yc managed-kubernetes cluster get --id $CLUSTER_ID --format json | jq -r .status)
    if [ "$STATUS" == "RUNNING" ]; then
        echo "Cluster is RUNNING"
        break
    fi
    echo "Current status: $STATUS. Waiting..."
    sleep 20
done

# 5. Создание node group (3 ноды как требуется в задании)
echo -e "${GREEN}5. Creating node group with 3 nodes...${NC}"
if ! yc managed-kubernetes node-group list --folder-id $YC_FOLDER_ID --format json | jq -r '.[].name' | grep -q "^vault-nodes$"; then
    echo "Creating node group..."
    yc managed-kubernetes node-group create \
      --name vault-nodes \
      --cluster-name $CLUSTER_NAME \
      --platform-id standard-v3 \
      --cores 2 \
      --memory 4 \
      --disk-type network-ssd \
      --disk-size 64 \
      --fixed-size 3 \
      --location zone=$YC_ZONE,subnet-id=$SUBNET_ID \
      --async
fi

# 6. Получение kubeconfig
echo -e "${GREEN}6. Getting kubeconfig...${NC}"
yc managed-kubernetes cluster get-credentials \
  --id $CLUSTER_ID \
  --external \
  --force

# 7. Ждем готовности нод
echo -e "${YELLOW}Waiting for nodes to be ready...${NC}"
sleep 60
kubectl wait --for=condition=Ready nodes --all --timeout=600s

echo -e "${GREEN}=== Infrastructure created successfully! ===${NC}"
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Nodes: 3"
echo ""
kubectl get nodes