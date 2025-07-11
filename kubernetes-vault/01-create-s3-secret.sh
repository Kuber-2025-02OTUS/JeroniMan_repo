#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Creating S3 Access Secret ===${NC}"

# Проверяем наличие файла с ключами
if [ ! -f "outputs/s3-access-key.json" ]; then
    echo -e "${RED}Error: outputs/s3-access-key.json not found!${NC}"
    echo "Please run ./00-create-infrastructure.sh first"
    exit 1
fi

# Извлекаем ключи
ACCESS_KEY=$(jq -r '.access_key.key_id' outputs/s3-access-key.json)
SECRET_KEY=$(jq -r '.secret' outputs/s3-access-key.json)

# Создаем namespace для CSI
echo "Creating namespace csi..."
kubectl create namespace csi --dry-run=client -o yaml | kubectl apply -f -

# Генерируем манифест секрета
cat > s3-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: csi-s3-secret
  namespace: csi
type: Opaque
stringData:
  accessKeyID: "${ACCESS_KEY}"
  secretAccessKey: "${SECRET_KEY}"
  endpoint: "https://storage.yandexcloud.net"
  region: "ru-central1"
EOF

# Применяем секрет
echo -e "${GREEN}Creating secret...${NC}"
kubectl apply -f s3-secret.yaml

# Проверяем создание
kubectl get secret csi-s3-secret -n csi

echo -e "${GREEN}Secret created successfully!${NC}"
echo "Manifest saved to: s3-secret.yaml"