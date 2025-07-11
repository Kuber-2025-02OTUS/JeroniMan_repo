                 #!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Creating Infrastructure for CSI Demo ===${NC}"

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
mkdir -p outputs

# Константы
CLUSTER_NAME="k8s-csi-cluster"
NETWORK_NAME="k8s-csi-network"
SUBNET_NAME="k8s-csi-subnet"
SUBNET_RANGE="10.0.4.0/24"
SA_CLUSTER_NAME="k8s-csi-cluster-sa"
SA_S3_NAME="k8s-csi-s3-sa"
BUCKET_NAME="k8s-csi-bucket-$(date +%s)"

# 1. Создание сервисного аккаунта для кластера
echo -e "${GREEN}1. Creating service account for cluster...${NC}"
if ! yc iam service-account get --name $SA_CLUSTER_NAME &>/dev/null; then
    yc iam service-account create --name $SA_CLUSTER_NAME \
      --description "Service account for CSI Kubernetes cluster"
fi

SA_CLUSTER_ID=$(yc iam service-account get --name $SA_CLUSTER_NAME --format json | jq -r .id)
echo "Cluster SA ID: $SA_CLUSTER_ID"

# Назначаем роли для кластера
for role in "editor" "container-registry.images.puller" "vpc.publicAdmin"; do
    yc resource-manager folder add-access-binding \
      --id $YC_FOLDER_ID \
      --role $role \
      --service-account-id $SA_CLUSTER_ID 2>/dev/null || true
done

# 2. Создание сервисного аккаунта для S3
echo -e "${GREEN}2. Creating service account for S3 access...${NC}"
if ! yc iam service-account get --name $SA_S3_NAME &>/dev/null; then
    yc iam service-account create --name $SA_S3_NAME \
      --description "Service account for S3 CSI access"
fi

SA_S3_ID=$(yc iam service-account get --name $SA_S3_NAME --format json | jq -r .id)
echo "S3 SA ID: $SA_S3_ID"

# Назначаем роли для S3
yc resource-manager folder add-access-binding \
  --id $YC_FOLDER_ID \
  --role storage.editor \
  --service-account-id $SA_S3_ID 2>/dev/null || true

# 3. Создание ключей доступа для S3
echo -e "${GREEN}3. Creating S3 access keys...${NC}"
if [ ! -f "outputs/s3-access-key.json" ]; then
    yc iam access-key create \
      --service-account-id $SA_S3_ID \
      --format json > outputs/s3-access-key.json
    echo "S3 access keys saved to outputs/s3-access-key.json"
else
    echo "S3 access keys already exist"
fi

# 4. Создание S3 bucket
echo -e "${GREEN}4. Creating S3 bucket...${NC}"
if ! yc storage bucket get --name $BUCKET_NAME &>/dev/null; then
    yc storage bucket create \
      --name $BUCKET_NAME \
      --default-storage-class standard \
      --max-size 10737418240
    echo $BUCKET_NAME > outputs/bucket-name.txt
    echo "Bucket created: $BUCKET_NAME"
else
    echo "Bucket already exists: $BUCKET_NAME"
fi

# 5. Создание сети
echo -e "${GREEN}5. Creating network...${NC}"
if ! yc vpc network get --name $NETWORK_NAME &>/dev/null; then
    yc vpc network create --name $NETWORK_NAME
fi
NETWORK_ID=$(yc vpc network get --name $NETWORK_NAME --format json | jq -r .id)

# 6. Создание подсети
echo -e "${GREEN}6. Creating subnet...${NC}"
if ! yc vpc subnet get --name $SUBNET_NAME &>/dev/null; then
    yc vpc subnet create \
      --name $SUBNET_NAME \
      --zone $YC_ZONE \
      --network-id $NETWORK_ID \
      --range $SUBNET_RANGE
fi
SUBNET_ID=$(yc vpc subnet get --name $SUBNET_NAME --format json | jq -r .id)

# 7. Создание кластера
echo -e "${GREEN}7. Creating Kubernetes cluster...${NC}"
if ! yc managed-kubernetes cluster get --name $CLUSTER_NAME &>/dev/null; then
    echo "Creating cluster (this will take 5-10 minutes)..."
    yc managed-kubernetes cluster create \
      --name $CLUSTER_NAME \
      --network-id $NETWORK_ID \
      --master-location zone=$YC_ZONE,subnet-id=$SUBNET_ID \
      --public-ip \
      --service-account-id $SA_CLUSTER_ID \
      --node-service-account-id $SA_CLUSTER_ID \
      --release-channel regular
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

# 8. Создание node group
echo -e "${GREEN}8. Creating node group...${NC}"
if ! yc managed-kubernetes node-group list --folder-id $YC_FOLDER_ID --format json | jq -r '.[].name' | grep -q "^csi-nodes$"; then
    echo "Creating node group..."
    yc managed-kubernetes node-group create \
      --name csi-nodes \
      --cluster-name $CLUSTER_NAME \
      --platform-id standard-v3 \
      --cores 2 \
      --memory 4 \
      --disk-type network-ssd \
      --disk-size 64 \
      --fixed-size 2 \
      --location zone=$YC_ZONE,subnet-id=$SUBNET_ID \
      --async
fi

# 9. Получение kubeconfig
echo -e "${GREEN}9. Getting kubeconfig...${NC}"
yc managed-kubernetes cluster get-credentials \
  --id $CLUSTER_ID \
  --external \
  --force

# 10. Ждем готовности нод
echo -e "${YELLOW}Waiting for nodes to be ready...${NC}"
sleep 60
kubectl wait --for=condition=Ready nodes --all --timeout=600s || true

echo -e "${GREEN}=== Infrastructure created successfully! ===${NC}"
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "S3 Bucket: $BUCKET_NAME"
echo "S3 Service Account: $SA_S3_NAME"
echo ""
echo "Access keys saved to: outputs/s3-access-key.json"
echo "Bucket name saved to: outputs/bucket-name.txt"
echo ""
kubectl get nodes