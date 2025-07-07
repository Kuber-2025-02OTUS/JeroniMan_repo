# Домашнее задание: Kubernetes Monitoring

## Описание

В данном домашнем задании настроен мониторинг кастомного nginx с использованием Prometheus Operator.

## Структура проекта

```
kubernetes-monitoring/
├── README.md
├── nginx/
│   ├── Dockerfile          # Кастомный образ nginx
│   └── nginx.conf         # Конфигурация с stub_status
├── namespace.yaml         # Namespace homework
├── deployment.yaml        # Pod с nginx и exporter
├── service.yaml          # Service для доступа
├── servicemonitor.yaml   # Конфигурация для Prometheus
├── install-prometheus.sh # Установка Prometheus Operator
└── apply.sh             # Скрипт деплоя
```

## Выполненные требования

✅ Создан кастомный образ nginx с endpoint `/stub_status` для метрик  
✅ Установлен Prometheus Operator через Helm  
✅ Создан deployment с кастомным nginx и service для него  
✅ Настроен nginx-prometheus-exporter (как sidecar контейнер)  
✅ Создан ServiceMonitor для сбора метрик  

## Архитектура решения

```
Pod: nginx-monitoring
┌─────────────────────────────────────────┐
│  nginx container     nginx-exporter     │
│  ┌─────────────┐    ┌────────────────┐ │
│  │   :80 (http)│    │                │ │
│  │   :8080     │───▶│ :9113 (metrics)│ │
│  │ (stub_status)    │                │ │
│  └─────────────┘    └────────────────┘ │
└─────────────────────────────────────────┘
                         ▼
                    Prometheus
```

## Компоненты

1. **Кастомный образ nginx** - с включенным модулем `stub_status` на порту 8080
2. **nginx-prometheus-exporter** - sidecar контейнер для преобразования метрик в формат Prometheus
3. **ServiceMonitor** - для автоматического обнаружения сервиса Prometheus'ом

## Установка

### 1. Установка Prometheus Operator

```bash
chmod +x install-prometheus.sh
./install-prometheus.sh
```

### 2. Сборка образа и деплой

```bash
chmod +x apply.sh
./apply.sh
```

## Проверка работоспособности

### Проверка метрик nginx

```bash
# Stub status напрямую
kubectl exec -n monitoring deployment/nginx-monitoring -c nginx -- \
  curl -s http://localhost:8080/stub_status

# Метрики через exporter
kubectl port-forward -n monitoring svc/nginx-monitoring 9113:9113
curl http://localhost:9113/metrics | grep nginx_
```
<img width="873" alt="Screenshot 2025-07-08 at 00 39 44" src="https://github.com/user-attachments/assets/16164816-3976-432c-a16b-0749392c8873" />
<img width="1017" alt="Screenshot 2025-07-08 at 00 40 10" src="https://github.com/user-attachments/assets/cd4488d1-e628-4da1-a208-aa944d4645c7" />


### Проверка в Prometheus

```bash
# Доступ к Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```
<img width="1511" alt="Screenshot 2025-07-08 at 00 40 36" src="https://github.com/user-attachments/assets/57d38bee-3e3d-45da-935e-50cc90c3301a" />

Откройте http://localhost:9090 и выполните запросы:
- `nginx_up` - статус доступности nginx
- `nginx_connections_active` - активные соединения
- `rate(nginx_http_requests_total[5m])` - RPS

## Метрики

- `nginx_connections_active` - текущее число активных соединений
- `nginx_connections_accepted` - общее число принятых соединений
- `nginx_connections_handled` - общее число обработанных соединений
- `nginx_http_requests_total` - общее число HTTP запросов
- `nginx_connections_reading` - соединения в состоянии чтения
- `nginx_connections_writing` - соединения в состоянии записи
- `nginx_connections_waiting` - ожидающие соединения
- `nginx_up` - статус доступности nginx (1 = up, 0 = down)

