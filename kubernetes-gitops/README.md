## Результат
<img width="1150" height="903" alt="Screenshot 2025-07-11 at 02 12 26" src="https://github.com/user-attachments/assets/f6d9049e-daf9-41e1-90f0-37f33f601c76" />

## Описание

Это домашнее задание по настройке GitOps с использованием ArgoCD в Kubernetes кластере Yandex Cloud.

## Структура проекта

```
kubernetes-gitops/
├── helm-charts/                    # Helm конфигурации
│   └── values-argocd.yaml         # Values для установки ArgoCD
├── manifests/                      # Kubernetes манифесты
│   └── argocd/                    # ArgoCD ресурсы
│       ├── project-otus.yaml      # ArgoCD Project
│       ├── app-kubernetes-networks.yaml     # Application (manual sync)
│       └── app-kubernetes-templating.yaml   # Application (auto sync)
├── scripts/                        # Скрипты автоматизации
│   ├── 00-create-infrastructure.sh # Создание инфраструктуры YC
│   ├── 01-setup-infrastructure.sh  # Настройка kubectl
│   ├── 02-deploy-argocd.sh        # Установка ArgoCD
│   ├── 03-configure-argocd.sh     # Настройка Project и Applications
│   └── cleanup.sh                 # Удаление ресурсов
└── outputs/                       # Генерируемые файлы (не коммитить!)
```

## Требования

- Yandex Cloud CLI (`yc`)
- kubectl
- Helm 3
- jq

## Быстрый старт

### 1. Настройка окружения

```bash
export YC_CLOUD_ID=<your-cloud-id>
export YC_FOLDER_ID=<your-folder-id>
export YC_ZONE=ru-central1-a
```

### 2. Создание инфраструктуры

```bash
cd scripts/
chmod +x *.sh

# Создание кластера и node pools
./00-create-infrastructure.sh

# Настройка kubectl
./01-setup-infrastructure.sh
```

### 3. Установка ArgoCD

```bash
# Установка ArgoCD через Helm
./02-deploy-argocd.sh

# Настройка Project и Applications
./03-configure-argocd.sh
```

## Компоненты

### Инфраструктура

- **Kubernetes кластер**: Managed Kubernetes в Yandex Cloud
- **Node pools**:
  - `workload-pool`: для обычных приложений
  - `infra-pool`: для инфраструктурных компонентов (с taint `node-role=infra:NoSchedule`)

### ArgoCD

ArgoCD устанавливается с помощью Helm chart со следующими особенностями:
- Все компоненты размещаются на infra нодах
- Настроены tolerations для обхода taint
- Отключен Dex (OIDC) для упрощения
- Включены метрики для мониторинга

**Команда установки:**
```bash
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --values helm-charts/values-argocd.yaml \
  --timeout 10m \
  --wait
```

### ArgoCD Project

**Project "otus"** создается для управления приложениями курса:
- Разрешены все namespace в текущем кластере
- Настроены роли admin и developer
- Поддержка создания namespace

### ArgoCD Applications

#### 1. kubernetes-networks
- **Sync Policy**: Manual
- **Namespace**: homework
- **Project**: otus
- **Особенности**: Требует ручной синхронизации

#### 2. kubernetes-templating
- **Sync Policy**: Auto (с Prune и Self Heal)
- **Namespace**: homeworkhelm
- **Project**: otus
- **Особенности**: 
  - Автоматическая синхронизация
  - Переопределение параметра `replicaCount=2`

## Использование

### Доступ к ArgoCD UI

```bash
# Port-forward
kubectl port-forward -n argocd svc/argocd-server 8080:80

# Получить пароль admin
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d

# Открыть в браузере
open http://localhost:8080
```

### ArgoCD CLI

```bash
# Установка CLI (macOS)
brew install argocd

# Логин
argocd login localhost:8080 \
  --username admin \
  --password <password> \
  --insecure

# Список приложений
argocd app list

# Синхронизация приложения
argocd app sync kubernetes-networks
```

### Управление приложениями

```bash
# Проверка статуса
kubectl get applications -n argocd

# Ручная синхронизация kubernetes-networks
argocd app sync kubernetes-networks

# Просмотр деталей приложения
kubectl describe application kubernetes-networks -n argocd
```

## Проверка работоспособности

```bash
# Проверка Project
kubectl get appproject otus -n argocd

# Проверка Applications
kubectl get applications -n argocd

# Проверка развернутых ресурсов
kubectl get all -n homework
kubectl get all -n homeworkhelm
```

## Очистка ресурсов

```bash
# Удаление всех ресурсов
./scripts/cleanup.sh
```

## Troubleshooting

### ArgoCD не может получить доступ к репозиторию

1. Проверьте URL репозитория в манифестах
2. Убедитесь, что репозиторий публичный
3. Для приватных репозиториев добавьте credentials:
   ```bash
   argocd repo add https://github.com/YOUR_USERNAME/YOUR_REPO \
     --username YOUR_USERNAME \
     --password YOUR_TOKEN
   ```

### Приложение не синхронизируется

1. Проверьте логи контроллера:
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
   ```

2. Проверьте события:
   ```bash
   kubectl get events -n argocd --sort-by='.lastTimestamp'
   ```

### Поды не размещаются на infra нодах

1. Проверьте labels и taints:
   ```bash
   kubectl get nodes --show-labels
   kubectl describe node <infra-node-name> | grep Taints
   ```

2. Убедитесь в правильности tolerations в values-argocd.yaml

## Результаты выполнения

1. ✅ ArgoCD установлен на infra ноды
2. ✅ Создан Project "otus"
3. ✅ Настроены два приложения с разными sync policies
4. ✅ kubernetes-networks с manual sync в namespace homework
5. ✅ kubernetes-templating с auto sync в namespace homeworkhelm

## Файлы для сдачи ДЗ

1. `helm-charts/values-argocd.yaml` - конфигурация установки ArgoCD
2. `manifests/argocd/project-otus.yaml` - манифест Project
3. `manifests/argocd/app-kubernetes-networks.yaml` - манифест Application (manual)
4. `manifests/argocd/app-kubernetes-templating.yaml` - манифест Application (auto)
5. Команда установки ArgoCD (указана выше)
