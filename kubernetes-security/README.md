# Домашнее задание по Kubernetes Security

## Выполненные задания

### Основное задание

1. **Создан ServiceAccount monitoring с доступом к /metrics**
   - Файл: `sa-monitoring.yaml`
   - ClusterRole для доступа к nonResourceURL `/metrics`
   - ClusterRoleBinding для связи SA с ролью

2. **Deployment использует ServiceAccount monitoring**
   - Файл: `deployment.yaml`
   - Добавлен `serviceAccountName: monitoring`

3. **Создан ServiceAccount cd с правами admin**
   - Файл: `sa-cd.yaml`
   - RoleBinding к встроенной ClusterRole `admin` в namespace homework

4. **Создан kubeconfig для ServiceAccount cd**
   - Скрипт: `generate-kubeconfig.sh`
   - Результат: `kubeconfig-cd.yaml`

5. **Сгенерирован токен на 1 день**
   - Скрипт: `generate-token.sh`
   - Результат сохранен в файл `token`

### Задание со звездочкой

**Модифицирован deployment для получения метрик**
- Файл: `deployment-with-metrics.yaml`
- Добавлен init контейнер `metrics-fetcher`
- Использует curl для обращения к `/metrics`
- Результат сохраняется в `metrics.html`
- Доступен по адресу `/metrics.html`

## Команды для проверки

```bash
# Применить все манифесты
chmod +x apply-all.sh
./apply-all.sh

# Проверить права ServiceAccount monitoring
kubectl auth can-i get /metrics --as=system:serviceaccount:homework:monitoring

# Проверить права ServiceAccount cd
kubectl auth can-i '*' '*' -n homework --as=system:serviceaccount:homework:cd

# Использовать kubeconfig
export KUBECONFIG=./kubeconfig-cd.yaml
kubectl get pods
kubectl create deployment test --image=nginx
kubectl delete deployment test

# Проверить metrics.html
kubectl port-forward <pod-name> 8000:8000 -n homework
curl http://localhost:8000/metrics.html
```

## Структура файлов

```
kubernetes-security/
├── namespace.yaml              # Namespace homework
├── sa-monitoring.yaml          # ServiceAccount monitoring + RBAC
├── sa-cd.yaml                  # ServiceAccount cd + RBAC
├── deployment.yaml             # Deployment с SA monitoring
├── deployment-with-metrics.yaml # Deployment с получением метрик (*)
├── generate-kubeconfig.sh      # Скрипт генерации kubeconfig
├── generate-token.sh           # Скрипт генерации токена
├── apply-all.sh               # Скрипт применения всех манифестов
├── kubeconfig-cd.yaml         # Сгенерированный kubeconfig
├── token                      # Сгенерированный токен
└── README.md                  # Этот файл
```

## Результаты

<img width="1000" alt="ServiceAccounts" src="screenshot1.png">
<img width="1000" alt="Metrics endpoint" src="screenshot2.png">

## Примечания

- Для Kubernetes 1.24+ используется команда `kubectl create token` для генерации временных токенов
- В старых версиях нужно создавать Secret вручную
- ServiceAccount monitoring имеет минимальные права только для чтения `/metrics`
- ServiceAccount cd имеет полные права admin в namespace homework