#!/bin/bash

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Checking Infrastructure Status ===${NC}"

# Определяем базовую директорию
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUTS_DIR="$BASE_DIR/outputs"

echo "Script dir: $SCRIPT_DIR"
echo "Base dir: $BASE_DIR"
echo "Outputs dir: $OUTPUTS_DIR"
echo ""

# Проверяем YC CLI
echo "1. Checking YC CLI..."
if command -v yc &>/dev/null; then
    echo -e "${GREEN}✓ YC CLI installed${NC}"
    yc version
else
    echo -e "${RED}✗ YC CLI not found${NC}"
fi

# Проверяем kubectl
echo ""
echo "2. Checking kubectl..."
if command -v kubectl &>/dev/null; then
    echo -e "${GREEN}✓ kubectl installed${NC}"
    kubectl version --client --short
else
    echo -e "${RED}✗ kubectl not found${NC}"
fi

# Проверяем подключение к кластеру
echo ""
echo "3. Checking cluster connection..."
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✓ Connected to cluster${NC}"
    kubectl cluster-info | head -2
else
    echo -e "${RED}✗ Not connected to cluster${NC}"
fi

# Проверяем outputs директорию
echo ""
echo "4. Checking outputs directory..."
if [ -d "$OUTPUTS_DIR" ]; then
    echo -e "${GREEN}✓ Outputs directory exists${NC}"
    echo "Contents:"
    ls -la "$OUTPUTS_DIR" | grep -E "\.(txt|json)$" || echo "  No output files found"
else
    echo -e "${RED}✗ Outputs directory not found${NC}"
    echo "Expected at: $OUTPUTS_DIR"
fi

# Проверяем необходимые файлы
echo ""
echo "5. Checking required files..."
REQUIRED_FILES=(
    "bucket-name.txt"
    "loki-s3-key.json"
    "nodes-with-labels.txt"
    "nodes-with-taints.txt"
)

ALL_GOOD=true
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$OUTPUTS_DIR/$file" ]; then
        echo -e "${GREEN}✓ $file${NC}"

        # Показываем содержимое для некоторых файлов
        case $file in
            "bucket-name.txt")
                echo "  Bucket: $(cat "$OUTPUTS_DIR/$file")"
                ;;
            "loki-s3-key.json")
                KEY_ID=$(jq -r .access_key.key_id "$OUTPUTS_DIR/$file" 2>/dev/null)
                echo "  Key ID: ${KEY_ID:0:20}..."
                ;;
        esac
    else
        echo -e "${RED}✗ $file not found${NC}"
        ALL_GOOD=false
    fi
done

# Проверяем ресурсы в облаке
echo ""
echo "6. Checking cloud resources..."

# Кластер
if yc managed-kubernetes cluster get k8s-logging-cluster &>/dev/null; then
    echo -e "${GREEN}✓ Cluster exists${NC}"
    STATUS=$(yc managed-kubernetes cluster get k8s-logging-cluster --format json | jq -r .status)
    echo "  Status: $STATUS"
else
    echo -e "${RED}✗ Cluster not found${NC}"
fi

# S3 bucket
if [ -f "$OUTPUTS_DIR/bucket-name.txt" ]; then
    BUCKET=$(cat "$OUTPUTS_DIR/bucket-name.txt")
    if yc storage bucket get --name "$BUCKET" &>/dev/null; then
        echo -e "${GREEN}✓ S3 bucket exists: $BUCKET${NC}"
    else
        echo -e "${RED}✗ S3 bucket not found: $BUCKET${NC}"
    fi
fi

# Итог
echo ""
if [ "$ALL_GOOD" = true ] && kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}=== Infrastructure is ready! ===${NC}"
    echo "You can proceed with: ./02-deploy-with-helm.sh"
else
    echo -e "${RED}=== Infrastructure is not ready! ===${NC}"
    echo "Please run: ./00-create-infrastructure.sh"
fi