#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Verifying Loki Installation ===${NC}"

# 1. Проверяем поды
echo -e "${YELLOW}Checking pods:${NC}"
kubectl get pods -n loki-stack -o wide

# 2. Проверяем распределение по нодам
echo -e "\n${YELLOW}Pod distribution:${NC}"
kubectl get pods -n loki-stack -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase

# 3. Проверяем готовность Loki
echo -e "\n${YELLOW}Testing Loki API:${NC}"

# Запускаем port-forward в фоне
kubectl port-forward -n loki-stack svc/loki-gateway 3100:80 &
PF_PID=$!
sleep 5

# Проверяем endpoints
echo "Checking /ready endpoint..."
if curl -s http://localhost:3100/ready | grep -q "ready"; then
    echo -e "${GREEN}✓ Loki is ready${NC}"
else
    echo -e "${RED}✗ Loki is not ready${NC}"
fi

echo -e "\nChecking /loki/api/v1/labels..."
LABELS=$(curl -s http://localhost:3100/loki/api/v1/labels)
if [ ! -z "$LABELS" ]; then
    echo -e "${GREEN}✓ Loki API is responding${NC}"
    echo "Available labels: $LABELS"
else
    echo -e "${RED}✗ Loki API is not responding${NC}"
fi

# Останавливаем port-forward
kill $PF_PID 2>/dev/null

# 4. Выводим инструкции для доступа
echo -e "\n${GREEN}=== Access Instructions ===${NC}"
echo "To access Loki UI:"
echo "  kubectl port-forward -n loki-stack svc/loki-gateway 3100:80"
echo "  Open: http://localhost:3100"
echo ""
echo "To query logs:"
echo "  curl 'http://localhost:3100/loki/api/v1/query_range?query={namespace=\"loki-stack\"}'"
echo ""
echo "To check metrics:"
echo "  curl http://localhost:3100/metrics"