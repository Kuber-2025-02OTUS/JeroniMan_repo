#!/bin/bash

echo "=== Настройка Docker для работы с Minikube ==="
eval $(minikube docker-env)

echo "=== Сборка Docker образа внутри Minikube ==="
cd nginx/
docker build -t nginx-custom:latest .
cd ..

echo "=== Проверка образа ==="
docker images | grep nginx-custom

echo "=== Применение манифестов Kubernetes ==="
kubectl apply -f namespace.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f servicemonitor.yaml

echo "=== Ожидание готовности подов ==="
kubectl wait --for=condition=ready pod -l app=nginx-monitoring -n homework --timeout=120s

echo "=== Проверка статуса ==="
kubectl get all -n monitoring
kubectl get servicemonitor -n monitoring

echo ""
echo "=== Проверка метрик ==="
echo "1. Nginx stub_status:"
kubectl run -it --rm curl --image=curlimages/curl -n monitoring -- \
  curl -s http://nginx-monitoring.homework.svc.cluster.local:8080/stub_status

echo ""
echo "2. Prometheus metrics:"
kubectl port-forward -n monitoring svc/nginx-monitoring 9113:9113 &
PF_PID=$!
sleep 3
curl -s http://localhost:9113/metrics | grep nginx_ | head -10
kill $PF_PID 2>/dev/null

echo ""
echo "Готово! Метрики доступны в Prometheus."