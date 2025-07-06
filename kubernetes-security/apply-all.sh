#!/bin/bash

echo "=== Применяем манифесты ==="
kubectl apply -f namespace.yaml
kubectl apply -f sa-monitoring.yaml
kubectl apply -f sa-cd.yaml

echo -e "\n=== Проверяем ServiceAccounts ==="
kubectl get sa -n homework

echo -e "\n=== Применяем deployment ==="
kubectl apply -f deployment.yaml

echo -e "\n=== Ждем запуска подов ==="
kubectl wait --for=condition=ready pod -l app=webserver -n homework --timeout=60s

echo -e "\n=== Генерируем kubeconfig для ServiceAccount cd ==="
chmod +x generate-kubeconfig.sh
./generate-kubeconfig.sh

echo -e "\n=== Генерируем токен для ServiceAccount cd ==="
chmod +x generate-token.sh
./generate-token.sh

echo -e "\n=== Тестируем kubeconfig ==="
KUBECONFIG=./kubeconfig-cd.yaml kubectl get pods -n homework

echo -e "\n=== Для задания со звездочкой применяем модифицированный deployment ==="
if [ -f "deployment-with-metrics.yaml" ]; then
    kubectl apply -f deployment-with-metrics.yaml
    echo "Ждем перезапуска подов..."
    sleep 30
    kubectl wait --for=condition=ready pod -l app=webserver -n homework --timeout=90s || true
else
    echo "ВНИМАНИЕ: deployment-with-metrics.yaml не найден!"
    echo "Скопируйте файл из артефакта k8s-deployment-metrics"
fi

echo -e "\n=== Проверяем доступность metrics.html ==="
POD=$(kubectl get pods -n homework -l app=webserver -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward $POD 8000:8000 -n homework &
PF_PID=$!
sleep 3

echo -e "\n=== Проверяем index.html ==="
curl -s http://localhost:8000/index.html | head -15

echo -e "\n=== Проверяем metrics.html ==="
curl -s http://localhost:8000/metrics.html | head -15

kill $PF_PID 2>/dev/null

echo -e "\n=== Готово! ==="