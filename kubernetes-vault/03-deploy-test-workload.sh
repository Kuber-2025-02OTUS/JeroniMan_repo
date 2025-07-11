#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Deploying Test Workload ===${NC}"

# 1. Создаем PVC
echo -e "${GREEN}Creating PVC...${NC}"
kubectl apply -f pvc.yaml

# Ждем создания PVC
echo -e "${YELLOW}Waiting for PVC to be bound...${NC}"
for i in {1..60}; do
    STATUS=$(kubectl get pvc csi-s3-pvc -n csi -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$STATUS" == "Bound" ]; then
        echo -e "${GREEN}PVC is bound!${NC}"
        break
    fi
    echo "Waiting for PVC... (attempt $i/60)"
    sleep 5
done

# Проверяем статус PVC
kubectl get pvc -n csi
kubectl describe pvc csi-s3-pvc -n csi

# 2. Деплоим тестовое приложение
echo -e "${GREEN}Deploying test workload...${NC}"
kubectl apply -f test-deployment.yaml

# 3. Ждем готовности подов
echo -e "${YELLOW}Waiting for pods to be ready...${NC}"
kubectl wait --for=condition=Ready pod -l app=csi-s3-test -n csi --timeout=300s || true

# 4. Проверяем статус
echo -e "${GREEN}Checking deployment status...${NC}"
kubectl get all -n csi
echo ""
kubectl get pv

# 5. Проверяем логи
echo -e "${GREEN}Checking logs...${NC}"
sleep 10
kubectl logs -n csi -l app=csi-s3-test --tail=20

echo ""
echo -e "${GREEN}=== Test workload deployed! ===${NC}"
echo ""
echo "To check files in S3:"
echo "1. Check logs: kubectl logs -n csi -l app=csi-s3-test -f"
echo "2. Exec into pod: kubectl exec -it -n csi csi-s3-test-pod -- sh"
echo "3. List files: kubectl exec -n csi csi-s3-test-pod -- ls -la /data/"