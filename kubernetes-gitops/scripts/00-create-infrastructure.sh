#!/bin/bash
set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Creating Kubernetes Infrastructure in Yandex Cloud ===${NC}"

# Определяем базовую директорию
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUTS_DIR="$BASE_DIR/outputs"

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

# Создаем директорию для outputs
echo "Creating outputs directory: $OUTPUTS_DIR"
mkdir -p "$OUTPUTS_DIR"

# Константы
CLUSTER_NAME="k8s-logging-cluster"
NETWORK_NAME="k8s-airflow-prod-network"  # Используем существующую сеть
SUBNET_NAME="k8s-logging-subnet"
SUBNET_RANGE="10.0.2.0/24"
SA_NAME="k8s-cluster-sa"
LOKI_SA_NAME="loki-s3-sa"
NAT_GATEWAY_NAME="k8s-nat-gateway"
ROUTE_TABLE_NAME="k8s-nat-route"

# 1. Создание сервисного аккаунта для кластера
echo -e "${GREEN}1. Creating service account for cluster...${NC}"
if ! yc iam service-account get --name $SA_NAME &>/dev/null; then
    yc iam service-account create --name $SA_NAME \
      --description "Service account for Kubernetes cluster"
    echo "Service account created"
else
    echo "Service account already exists"
fi

SA_ID=$(yc iam service-account get --name $SA_NAME --format json | jq -r .id)
echo "Service account ID: $SA_ID"

# Назначаем роли
echo "Assigning roles..."
for role in "editor" "container-registry.images.puller" "vpc.publicAdmin"; do
    yc resource-manager folder add-access-binding \
      --id $YC_FOLDER_ID \
      --role $role \
      --service-account-id $SA_ID 2>/dev/null || echo "Role $role already assigned"
done

# 2. Проверка и создание сети
echo -e "${GREEN}2. Setting up network...${NC}"

# Проверяем существующую сеть
NETWORK_ID=$(yc vpc network get --name $NETWORK_NAME --format json 2>/dev/null | jq -r .id)
if [ -z "$NETWORK_ID" ] || [ "$NETWORK_ID" == "null" ]; then
    echo -e "${YELLOW}Network $NETWORK_NAME not found. Creating new network...${NC}"
    NETWORK_NAME="k8s-logging-network"
    yc vpc network create --name $NETWORK_NAME \
      --description "Network for Kubernetes logging"
    NETWORK_ID=$(yc vpc network get --name $NETWORK_NAME --format json | jq -r .id)
fi
echo "Network ID: $NETWORK_ID"

# 3. Создание NAT Gateway для доступа в интернет
echo -e "${GREEN}3. Setting up NAT Gateway for internet access...${NC}"

# Проверяем существует ли NAT gateway
GATEWAY_ID=$(yc vpc gateway list --format json | jq -r '.[] | select(.name=="'$NAT_GATEWAY_NAME'") | .id')
if [ -z "$GATEWAY_ID" ] || [ "$GATEWAY_ID" == "null" ]; then
    echo "Creating NAT gateway..."
    yc vpc gateway create --name $NAT_GATEWAY_NAME
    GATEWAY_ID=$(yc vpc gateway list --format json | jq -r '.[] | select(.name=="'$NAT_GATEWAY_NAME'") | .id')
    echo "NAT Gateway created with ID: $GATEWAY_ID"
else
    echo "NAT Gateway already exists with ID: $GATEWAY_ID"
fi

# Создаем таблицу маршрутизации
ROUTE_TABLE_ID=$(yc vpc route-table list --format json | jq -r '.[] | select(.name=="'$ROUTE_TABLE_NAME'") | .id')
if [ -z "$ROUTE_TABLE_ID" ] || [ "$ROUTE_TABLE_ID" == "null" ]; then
    echo "Creating route table..."
    yc vpc route-table create \
      --name $ROUTE_TABLE_NAME \
      --network-id $NETWORK_ID \
      --route destination=0.0.0.0/0,gateway-id=$GATEWAY_ID
    ROUTE_TABLE_ID=$(yc vpc route-table list --format json | jq -r '.[] | select(.name=="'$ROUTE_TABLE_NAME'") | .id')
    echo "Route table created with ID: $ROUTE_TABLE_ID"
else
    echo "Route table already exists with ID: $ROUTE_TABLE_ID"
fi

# 4. Создаем подсеть с NAT
echo -e "${GREEN}4. Setting up subnet with NAT routing...${NC}"

if ! yc vpc subnet get --name $SUBNET_NAME &>/dev/null; then
    echo "Creating subnet: $SUBNET_NAME"
    yc vpc subnet create \
      --name $SUBNET_NAME \
      --zone $YC_ZONE \
      --network-id $NETWORK_ID \
      --range $SUBNET_RANGE \
      --route-table-id $ROUTE_TABLE_ID \
      --description "Subnet for Kubernetes logging homework with NAT"
else
    echo "Subnet already exists, updating route table..."
    # Обновляем существующую подсеть для использования NAT
    yc vpc subnet update $SUBNET_NAME --route-table-id $ROUTE_TABLE_ID
fi

SUBNET_ID=$(yc vpc subnet get --name $SUBNET_NAME --format json | jq -r .id)
echo "Subnet ID: $SUBNET_ID"

# 5. Создание Kubernetes кластера
echo -e "${GREEN}5. Creating Kubernetes cluster...${NC}"
if ! yc managed-kubernetes cluster get --name $CLUSTER_NAME &>/dev/null; then
    echo "Creating cluster (this will take 5-10 minutes)..."
    yc managed-kubernetes cluster create \
      --name $CLUSTER_NAME \
      --network-id $NETWORK_ID \
      --master-location zone=$YC_ZONE,subnet-id=$SUBNET_ID \
      --public-ip \
      --service-account-id $SA_ID \
      --node-service-account-id $SA_ID \
      --release-channel regular
else
    echo "Cluster already exists"
fi

# Получаем ID кластера
CLUSTER_ID=$(yc managed-kubernetes cluster get --name $CLUSTER_NAME --format json | jq -r .id)
echo "Cluster ID: $CLUSTER_ID"

# Ждем готовности кластера
echo -e "${YELLOW}Waiting for cluster to be RUNNING...${NC}"
while true; do
    STATUS=$(yc managed-kubernetes cluster get --id $CLUSTER_ID --format json | jq -r .status)
    HEALTH=$(yc managed-kubernetes cluster get --id $CLUSTER_ID --format json | jq -r .health)

    if [ "$STATUS" == "RUNNING" ]; then
        echo "Cluster is RUNNING (health: $HEALTH)"
        break
    fi
    echo "Current status: $STATUS. Waiting..."
    sleep 20
done

# 6. Создание node pools
echo -e "${GREEN}6. Creating node pools...${NC}"

# Workload pool
if ! yc managed-kubernetes node-group list --folder-id $YC_FOLDER_ID --format json | jq -r '.[].name' | grep -q "^workload-pool$"; then
    echo "Creating workload pool..."
    yc managed-kubernetes node-group create \
      --name workload-pool \
      --cluster-name $CLUSTER_NAME \
      --platform-id standard-v3 \
      --cores 2 \
      --memory 4 \
      --disk-type network-ssd \
      --disk-size 64 \
      --fixed-size 1 \
      --location zone=$YC_ZONE,subnet-id=$SUBNET_ID \
      --async
else
    echo "Workload pool already exists"
fi

# Infra pool с taint
if ! yc managed-kubernetes node-group list --folder-id $YC_FOLDER_ID --format json | jq -r '.[].name' | grep -q "^infra-pool$"; then
    echo "Creating infra pool with taints..."
    yc managed-kubernetes node-group create \
      --name infra-pool \
      --cluster-name $CLUSTER_NAME \
      --platform-id standard-v3 \
      --cores 2 \
      --memory 8 \
      --disk-type network-ssd \
      --disk-size 100 \
      --fixed-size 1 \
      --location zone=$YC_ZONE,subnet-id=$SUBNET_ID \
      --node-taints node-role=infra:NoSchedule \
      --node-labels node-role=infra \
      --async
else
    echo "Infra pool already exists"
fi

# Ждем создания node groups
echo -e "${YELLOW}Waiting for node groups to be created...${NC}"
sleep 30

# 7. Создание S3 для Loki
echo -e "${GREEN}7. Creating S3 bucket for Loki...${NC}"

# Создаем SA для S3
if ! yc iam service-account get --name $LOKI_SA_NAME &>/dev/null; then
    yc iam service-account create --name $LOKI_SA_NAME \
      --description "Service account for Loki S3 access"
fi

LOKI_SA_ID=$(yc iam service-account get --name $LOKI_SA_NAME --format json | jq -r .id)

yc resource-manager folder add-access-binding \
  --id $YC_FOLDER_ID \
  --role storage.editor \
  --service-account-id $LOKI_SA_ID 2>/dev/null || true

# Создаем ключи доступа
if [ ! -f "$OUTPUTS_DIR/loki-s3-key.json" ]; then
    echo "Creating S3 access keys..."
    yc iam access-key create \
      --service-account-id $LOKI_SA_ID \
      --format json > "$OUTPUTS_DIR/loki-s3-key.json"
    echo "S3 keys saved to: $OUTPUTS_DIR/loki-s3-key.json"
fi

# Создаем бакет
if [ ! -f "$OUTPUTS_DIR/bucket-name.txt" ]; then
    BUCKET_NAME="k8s-logging-loki-$(date +%s)"
    echo "Creating S3 bucket: $BUCKET_NAME"
    yc storage bucket create \
      --name $BUCKET_NAME \
      --default-storage-class standard \
      --max-size 10737418240
    echo $BUCKET_NAME > "$OUTPUTS_DIR/bucket-name.txt"
    echo "Bucket name saved to: $OUTPUTS_DIR/bucket-name.txt"
else
    BUCKET_NAME=$(cat "$OUTPUTS_DIR/bucket-name.txt")
    echo "Using existing bucket: $BUCKET_NAME"
fi

## 8. Создание Container Registry
#echo -e "${GREEN}8. Creating Container Registry...${NC}"
#REGISTRY_ID=$(yc container registry list --format json | jq -r '.[0].id')
#if [ -z "$REGISTRY_ID" ] || [ "$REGISTRY_ID" == "null" ]; then
#    echo "Creating container registry..."
#    yc container registry create --name k8s-logging-registry
#    REGISTRY_ID=$(yc container registry list --format json | jq -r '.[0].id')
#fi
#echo "cr.yandex/${REGISTRY_ID}" > "$OUTPUTS_DIR/ycr-endpoint.txt"
#echo "Registry endpoint saved to: $OUTPUTS_DIR/ycr-endpoint.txt"

# 9. Итоговая информация
echo -e "${GREEN}=== Infrastructure created successfully! ===${NC}"
echo ""
echo "Cluster name: $CLUSTER_NAME"
echo "Cluster ID: $CLUSTER_ID"
echo "Network: $NETWORK_NAME ($NETWORK_ID)"
echo "Subnet: $SUBNET_NAME ($SUBNET_ID)"
echo "NAT Gateway: $NAT_GATEWAY_NAME ($GATEWAY_ID)"
echo "Route Table: $ROUTE_TABLE_NAME ($ROUTE_TABLE_ID)"
echo "S3 bucket: $BUCKET_NAME"
echo "Container Registry: cr.yandex/${REGISTRY_ID}"
echo ""
echo "Service accounts:"
echo "- Cluster SA: $SA_NAME ($SA_ID)"
echo "- Loki S3 SA: $LOKI_SA_NAME ($LOKI_SA_ID)"
echo ""
echo -e "${GREEN}Internet access is configured via NAT Gateway!${NC}"
echo "Nodes can now pull images from Docker Hub and other external registries."
echo ""
echo "Output files saved in: $OUTPUTS_DIR"
ls -la "$OUTPUTS_DIR/"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Wait for node pools to be ready (5-10 minutes)"
echo "2. Run ./01-setup-infrastructure.sh to configure kubectl"
echo "3. Run ./02-deploy-with-helm.sh to deploy Loki stack"