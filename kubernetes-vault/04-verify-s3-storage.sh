#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Verifying S3 Storage ===${NC}"

# Получаем имя бакета
if [ ! -f "outputs/bucket-name.txt" ]; then
    echo -e "${RED}Error: outputs/bucket-name.txt not found!${NC}"
    exit 1
fi

BUCKET_NAME=$(cat outputs/bucket-name.txt)
echo "Bucket: $BUCKET_NAME"

# 1. Проверяем файлы в поде
echo -e "${YELLOW}1. Checking files in pod...${NC}"
echo "Files in /data directory:"
kubectl exec -n csi csi-s3-test-pod -- ls -la /data/ || echo "Pod not ready yet"

# 2. Создаем тестовый файл
echo -e "${YELLOW}2. Creating test file...${NC}"
TEST_FILE="manual-test-$(date +%s).txt"
kubectl exec -n csi csi-s3-test-pod -- sh -c "echo 'Manual test at $(date)' > /data/$TEST_FILE"
echo "Created file: $TEST_FILE"

# 3. Читаем файл обратно
echo -e "${YELLOW}3. Reading file back...${NC}"
kubectl exec -n csi csi-s3-test-pod -- cat /data/$TEST_FILE

# 4. Проверяем файлы в S3
echo -e "${YELLOW}4. Checking files in S3 bucket...${NC}"

# Получаем PV name
PV_NAME=$(kubectl get pvc csi-s3-pvc -n csi -o jsonpath='{.spec.volumeName}')
echo "PV Name: $PV_NAME"

# Проверяем через yc CLI
echo "Listing objects in S3 bucket:"
yc storage s3api list-objects --bucket $BUCKET_NAME --prefix "$PV_NAME/" | jq '.Contents[]?.Key' || echo "No objects found yet"

# 5. Альтернативный способ проверки через s3cmd
if command -v s3cmd &> /dev/null; then
    echo -e "${YELLOW}5. Checking with s3cmd...${NC}"

    # Создаем конфиг для s3cmd
    ACCESS_KEY=$(jq -r '.access_key.key_id' outputs/s3-access-key.json)
    SECRET_KEY=$(jq -r '.secret' outputs/s3-access-key.json)

    cat > ~/.s3cfg <<EOF
[default]
access_key = $ACCESS_KEY
secret_key = $SECRET_KEY
bucket_location = ru-central1
host_base = storage.yandexcloud.net
host_bucket = %(bucket)s.storage.yandexcloud.net
use_https = True
EOF

    s3cmd ls s3://$BUCKET_NAME/
fi

# 6. Проверяем работу deployment
echo -e "${YELLOW}6. Checking deployment logs...${NC}"
echo "Last 10 log entries from deployment:"
kubectl logs -n csi -l app=csi-s3-test --tail=10

# 7. Статистика
echo -e "${GREEN}=== Summary ===${NC}"
echo "PVC Status:"
kubectl get pvc -n csi

echo ""
echo "Pod Status:"
kubectl get pods -n csi

echo ""
echo "To manually check S3 bucket:"
echo "1. Via YC Console: https://console.cloud.yandex.ru/folders/${YC_FOLDER_ID}/storage/buckets/${BUCKET_NAME}"
echo "2. Via CLI: yc storage s3api list-objects --bucket $BUCKET_NAME"
echo ""
echo -e "${GREEN}Verification complete!${NC}"