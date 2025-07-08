#!/bin/bash

echo "=== Установка Prometheus Operator через Helm ==="

# Добавляем репозиторий prometheus-community
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Создаем namespace для мониторинга
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Устанавливаем kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin \
  --wait

echo "=== Prometheus Operator установлен ==="
echo ""
echo "Доступ к сервисам:"
echo "Prometheus: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "Grafana: kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
echo "Alertmanager: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093"
echo ""
echo "Grafana credentials: admin/admin"