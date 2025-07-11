#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Running Complete CSI S3 Setup ===${NC}"

# Проверка переменных окружения
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

# Делаем все скрипты исполняемыми
chmod +x *.sh

# Запускаем скрипты по порядку
scripts=(
    "00-create-infrastructure.sh"
    "01-create-s3-secret.sh"
    "02-install-csi-driver.sh"
    "03-deploy-test-workload.sh"
    "04-verify-s3-storage.sh"
)

for script in "${scripts[@]}"; do
    echo ""
    echo -e "${YELLOW}=== Running $script ===${NC}"
    ./$script

    # Небольшая пауза между скриптами
    sleep 5
done

echo ""
echo -e "${GREEN}=== All steps completed successfully! ===${NC}"
echo ""
echo "Summary:"
echo "- Cluster: k8s-csi-cluster"
echo "- Bucket: $(cat outputs/bucket-name.txt)"
echo "- StorageClass: csi-s3"
echo "- PVC: csi-s3-pvc in namespace csi"
echo ""
echo "Check S3 files:"
echo "kubectl exec -n csi csi-s3-test-pod -- ls -la /data/"
echo ""
echo "Check logs:"
echo "kubectl logs -n csi -l app=csi-s3-test -f"