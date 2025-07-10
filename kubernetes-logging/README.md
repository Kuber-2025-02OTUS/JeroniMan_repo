# Kubernetes Logging Homework

## Описание

Домашнее задание по настройке централизованного логирования в Kubernetes с использованием Loki и Promtail в Yandex Cloud.

## Архитектура решения

- **Managed Kubernetes** в Yandex Cloud с двумя пулами нод
- **Loki** для хранения и обработки логов
- **Promtail** как DaemonSet для сбора логов со всех нод
- **Grafana** для визуализации логов
- **Yandex Object Storage (S3)** для долговременного хранения
- **Публичные Docker образы** (решение проблемы с доступом к registry)

## Методы развертывания

### 1. Helm Charts (рекомендуется)
- **Включает:** Loki + Promtail + Grafana + опционально Prometheus
- **Плюсы:** Полный стек мониторинга, готовые дашборды, простое обновление
- **Файлы:** `helm-charts/`

### 2. Raw Manifests
- **Включает:** Loki + Promtail
- **Плюсы:** Полный контроль, минимальная конфигурация
- **Файлы:** `manifests/`

## Структура проекта

```
kubernetes-logging/
├── README.md                    # Этот файл
├── manifests/                   # Raw Kubernetes манифесты
│   ├── namespace.yaml
│   ├── loki/
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   └── promtail/
│       ├── configmap.yaml
│       ├── daemonset.yaml
│       └── rbac.yaml
├── helm-charts/                 # Helm конфигурации
│   ├── README.md
│   ├── .gitignore
│   ├── values-loki.yaml
│   ├── values-prometheus.yaml
│   └── values-loki-s3-override.yaml
├── scripts/                     # Скрипты автоматизации
│   ├── 00-create-infrastructure.sh  # Создание инфраструктуры
│   ├── 01-setup-infrastructure.sh   # Настройка kubectl
│   ├── 02-deploy-with-helm.sh       # Деплой через Helm
│   ├── 02-deploy-with-manifests.sh  # Деплой через манифесты
│   ├── 05-verify-installation.sh    # Проверка установки
│   ├── check-infrastructure.sh      # Проверка готовности
│   ├── install-helm.sh             # Установка Helm
│   └── cleanup.sh                  # Удаление всего
├── docs/                           # Дополнительная документация
│   ├── TROUBLESHOOTING.md
│   └── DEPLOYMENT_METHODS.md
└── outputs/                        # Генерируемые файлы (не коммитить!)
    ├── bucket-name.txt
    ├── loki-s3-key.json
    ├── nodes-with-labels.txt
    ├── nodes-with-taints.txt
    └── ycr-endpoint.txt
```

## Быстрый старт

### Требования

- **yc** (Yandex Cloud CLI) - [установка](https://cloud.yandex.ru/docs/cli/quickstart)
- **kubectl** - [установка](https://kubernetes.io/docs/tasks/tools/)
- **jq** - для работы с JSON
- **envsubst** - часть пакета `gettext`
- **helm** - для Helm метода [установка](https://helm.sh/docs/intro/install/)

### Установка переменных окружения

```bash
export YC_CLOUD_ID=<your-cloud-id>
export YC_FOLDER_ID=<your-folder-id>
export YC_ZONE=ru-central1-a
```

### Установка

```bash
# 1. Клонируйте репозиторий
git clone <repository>
cd kubernetes-logging/scripts

# 2. Сделайте скрипты исполняемыми
chmod +x *.sh

# 3. Создайте инфраструктуру и установите Loki
./00-create-infrastructure.sh
./01-setup-infrastructure.sh
./02-deploy-with-helm.sh  # или ./02-deploy-with-manifests.sh
```

## Проверка установки

```bash
# Автоматическая проверка
./scripts/05-verify-installation.sh

# Ручная проверка
kubectl get pods -n loki-stack
kubectl logs -n loki-stack -l app=loki --tail=50
```

## Доступ к сервисам

### Grafana (только Helm метод)
```bash
kubectl port-forward -n loki-stack svc/loki-grafana 3000:80
# URL: http://localhost:3000
# Login: admin / admin
```

### Loki API (оба метода)
```bash
kubectl port-forward -n loki-stack svc/loki 3100:3100
# URL: http://localhost:3100
```

## Примеры запросов LogQL

```bash
# Все логи из namespace
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={namespace="loki-stack"}'

# Поиск ошибок
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={namespace="kube-system"} |= "error"'

# Логи конкретного пода
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={pod="loki-0"}'

# Логи за последний час
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="kube-system/kube-proxy"}' \
  --data-urlencode 'start='$(date -u -d '1 hour ago' +%s)'000000000' \
  --data-urlencode 'end='$(date +%s)'000000000'
```

## Решение проблем

### Pod не стартует / ImagePullBackOff

Проблема с доступом к Container Registry из Managed K8s. Решение:
- Используются публичные образы из Docker Hub
- Не требуется настройка YCR или imagePullSecrets

### Проверка логов компонентов

```bash
# Логи Loki
kubectl logs -n loki-stack deployment/loki -f

# Логи Promtail (все поды)
kubectl logs -n loki-stack -l app=promtail -f --prefix=true

# События в namespace
kubectl get events -n loki-stack --sort-by='.lastTimestamp'
```

### Проверка что Promtail собирает логи

```bash
# Создать тестовый под
kubectl run test-logger --image=busybox -- sh -c "while true; do echo 'Test log message'; sleep 5; done"

# Подождать 30 секунд и проверить в Loki
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={pod="test-logger"}'

# Удалить тестовый под
kubectl delete pod test-logger
```

## Очистка ресурсов

```bash
cd scripts
./cleanup.sh

# Скрипт удалит:
# - Kubernetes namespace loki-stack
# - Node groups и кластер
# - S3 bucket с логами
# - Service accounts
# - Сеть и подсети (опционально)
```

## Выполненные требования ДЗ

- ✅ Managed Kubernetes cluster в Yandex Cloud
- ✅ 2 пула нод:
  - workload-pool - для обычной нагрузки
  - infra-pool - для инфраструктурных сервисов
- ✅ Taint `node-role=infra:NoSchedule` для инфра-нод
- ✅ S3 bucket для хранения логов
- ✅ Loki в SingleBinary режиме
- ✅ Размещение только на infra-нодах (nodeSelector + tolerations)
- ✅ auth_enabled: false
- ✅ Выводы команд сохранены в `outputs/`:
  - `kubectl get node -o wide --show-labels` → `nodes-with-labels.txt`
  - Информация о taints → `nodes-with-taints.txt`

## Особенности реализации

1. **Публичные образы вместо YCR** - обход проблемы с сетевой доступностью в Managed K8s
2. **Два метода развертывания** - Helm для полного стека, манифесты для минимальной установки
3. **Автоматизация** - скрипты для всех этапов от создания до удаления
4. **Консистентные пути** - все скрипты используют единую структуру директорий
5. **Идемпотентность** - скрипты можно запускать многократно

## Конфигурация компонентов

### Loki
- **Режим**: SingleBinary (монолитный)
- **Порт**: 3100 (HTTP API), 9096 (gRPC)
- **Хранилище**: Yandex Object Storage (S3)
- **Retention**: 720 часов (30 дней)
- **Schema**: v13 с TSDB индексом
- **Размещение**: только на infra нодах

### Promtail
- **Тип**: DaemonSet (запускается на всех нодах)
- **Сбор логов**: из /var/log/pods/
- **Pipeline**: CRI парсер для контейнерных логов
- **Endpoint**: http://loki:3100/loki/api/v1/push
- **Tolerations**: для запуска на всех нодах включая infra

### Grafana (только Helm)
- **Datasource**: Loki автоматически настроен
- **Размещение**: только на infra нодах
- **Доступ**: admin / admin

## Полезные команды

```bash
# Посмотреть все лейблы в Loki
curl -s http://localhost:3100/loki/api/v1/labels | jq

# Посмотреть значения лейбла
curl -s "http://localhost:3100/loki/api/v1/label/namespace/values" | jq

# Статус Promtail
kubectl exec -n loki-stack daemonset/promtail -- wget -O- -q localhost:9080/targets

# Метрики Loki
curl -s http://localhost:3100/metrics | grep -i loki_

# Проверить конфигурацию S3
kubectl get cm loki-config -n loki-stack -o yaml | grep -A10 s3:
```

## Дополнительная документация

- [LogQL - язык запросов](https://grafana.com/docs/loki/latest/logql/)
- [Loki HTTP API](https://grafana.com/docs/loki/latest/api/)
- [Promtail конфигурация](https://grafana.com/docs/loki/latest/clients/promtail/configuration/)
- [Yandex Managed Kubernetes](https://cloud.yandex.ru/docs/managed-kubernetes/)
- [Yandex Object Storage](https://cloud.yandex.ru/docs/storage/)

## Автор

Выполнено в рамках курса "Инфраструктурная платформа на основе Kubernetes-2025-02" OTUS


## Результаты
<img width="1644" height="1172" alt="Screenshot 2025-07-11 at 00 45 24" src="https://github.com/user-attachments/assets/5de70ae8-5522-457e-b1cb-2f4ac9ba00c9" />
<img width="1646" height="1286" alt="Screenshot 2025-07-11 at 00 45 09" src="https://github.com/user-attachments/assets/ac5d1df9-e246-4aaa-bdc7-98aa24644681" />
<img width="1424" height="417" alt="Screenshot 2025-07-11 at 00 37 17" src="https://github.com/user-attachments/assets/17126e54-30b0-413c-9545-2cb33226fa7a" />
<img width="1112" height="329" alt="Screenshot 2025-07-11 at 00 36 07" src="https://github.com/user-attachments/assets/1c14cfa5-879c-41a7-ba30-9a56a57afab7" />
<img width="1644" height="1358" alt="Screenshot 2025-07-11 at 00 35 58" src="https://github.com/user-attachments/assets/2afb3662-31e9-4876-8254-6b11696a0cf6" />
<img width="1642" height="1359" alt="Screenshot 2025-07-11 at 00 35 49" src="https://github.com/user-attachments/assets/d5e3825a-14a9-4f4a-a359-ec7eb1c02714" />

