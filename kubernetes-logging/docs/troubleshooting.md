# Troubleshooting Guide

## Распространенные проблемы и их решения

### 1. ImagePullBackOff / ErrImagePull

**Симптомы:**
```
Events:
  Warning  Failed     2m    kubelet  Failed to pull image "cr.yandex/..."
  Warning  Failed     2m    kubelet  Error: ErrImagePull
```

**Причина:** 
Managed Kubernetes кластер не может достучаться до Container Registry из-за сетевых ограничений.

**Решение:**
В текущей реализации используются публичные образы из Docker Hub:
- `grafana/loki:2.9.8`
- `grafana/promtail:2.9.8`
- `grafana/grafana:latest`

Если все равно возникают проблемы:
```bash
# Проверьте что в deployment используются публичные образы
kubectl get deployment loki -n loki-stack -o yaml | grep image:

# Обновите образ вручную если нужно
kubectl set image deployment/loki loki=grafana/loki:2.9.8 -n loki-stack
```

### 2. Pod не запускается на infra ноде

**Симптомы:**
```
0/2 nodes are available: 1 node(s) had taint {node-role: infra}, that the pod didn't tolerate
```

**Причина:** 
Не настроены tolerations для taint `node-role=infra:NoSchedule`.

**Решение:**
Проверьте что в values файле или манифесте есть:
```yaml
tolerations:
- key: node-role
  operator: Equal
  value: infra
  effect: NoSchedule

nodeSelector:
  node-role: infra
```

### 3. Promtail не видит логи

**Симптомы:**
- В Loki нет логов от подов
- `curl http://localhost:3100/loki/api/v1/labels` возвращает пустой список

**Диагностика:**
```bash
# Проверьте что Promtail запущен на всех нодах
kubectl get pods -n loki-stack -l app=promtail -o wide

# Проверьте логи Promtail
kubectl logs -n loki-stack -l app=promtail --tail=50

# Проверьте targets в Promtail
kubectl port-forward -n loki-stack daemonset/promtail 9080:9080
curl http://localhost:9080/targets
```

**Решение:**
1. Убедитесь что Promtail имеет правильные RBAC права:
```bash
kubectl get clusterrole promtail -o yaml
kubectl get clusterrolebinding promtail -o yaml
```

2. Проверьте что путь к логам правильный:
```bash
kubectl exec -n loki-stack -it <promtail-pod> -- ls -la /var/log/pods/
```

### 4. Loki не может записать в S3

**Симптомы:**
```
level=error ts=2024-01-01T00:00:00.000Z caller=flush.go:146 msg="failed to flush" err="AccessDenied"
```

**Диагностика:**
```bash
# Проверьте credentials в ConfigMap
kubectl get configmap loki-config -n loki-stack -o yaml | grep -A5 s3:

# Проверьте что bucket существует
BUCKET=$(cat outputs/bucket-name.txt)
yc storage bucket get --name $BUCKET
```

**Решение:**
```bash
# Пересоздайте ключи доступа
LOKI_SA_ID=$(yc iam service-account get --name loki-s3-sa --format json | jq -r .id)
yc iam access-key create \
  --service-account-id $LOKI_SA_ID \
  --format json > outputs/loki-s3-key.json

# Переразверните Loki
cd scripts
./02-deploy-with-helm.sh  # или ./02-deploy-with-manifests.sh
```

### 5. Grafana не может подключиться к Loki

**Симптомы:**
- В Grafana при выборе datasource Loki: "Data source is not working"

**Решение:**
1. Проверьте что Loki service существует:
```bash
kubectl get svc -n loki-stack | grep loki
```

2. Проверьте правильность URL в datasource:
- Должно быть: `http://loki:3100`
- НЕ `http://localhost:3100`

3. Пересоздайте datasource:
```bash
kubectl exec -n loki-stack deployment/loki-grafana -- \
  curl -X POST http://admin:admin@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Loki",
    "type": "loki",
    "url": "http://loki:3100",
    "access": "proxy",
    "isDefault": true
  }'
```

### 6. Нет доступа к Grafana UI

**Симптомы:**
- `kubectl port-forward` работает, но страница не открывается

**Решение:**
```bash
# Проверьте что pod запущен
kubectl get pods -n loki-stack -l app.kubernetes.io/name=grafana

# Проверьте логи
kubectl logs -n loki-stack -l app.kubernetes.io/name=grafana

# Альтернативный port-forward
kubectl port-forward -n loki-stack deployment/loki-grafana 3000:3000

# Проверьте что порт 3000 не занят
lsof -i :3000 || netstat -an | grep 3000
```

### 7. Высокое потребление памяти/CPU

**Симптомы:**
- Pod постоянно перезапускается с OOMKilled
- Высокая нагрузка на ноду

**Решение:**
1. Увеличьте лимиты ресурсов:
```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 1000m
    memory: 2Gi
```

2. Настройте retention для уменьшения объема данных:
```yaml
limits_config:
  retention_period: 168h  # 7 дней вместо 30
```

### 8. Нет логов от системных компонентов

**Симптомы:**
- Нет логов из kube-system namespace

**Решение:**
Убедитесь что Promtail запущен на всех нодах включая master:
```yaml
tolerations:
- effect: NoSchedule
  operator: Exists
- effect: NoExecute
  operator: Exists
```

## Полезные команды для диагностики

### Проверка состояния компонентов
```bash
# Все поды в namespace
kubectl get pods -n loki-stack -o wide

# События за последний час
kubectl get events -n loki-stack --sort-by='.lastTimestamp' | head -20

# Использование ресурсов
kubectl top pods -n loki-stack
```

### Проверка логов
```bash
# Логи с таймстампами
kubectl logs -n loki-stack deployment/loki --timestamps=true --tail=100

# Логи всех контейнеров в поде
kubectl logs -n loki-stack <pod-name> --all-containers=true

# Предыдущие логи (если под перезапускался)
kubectl logs -n loki-stack <pod-name> --previous
```

### Проверка конфигурации
```bash
# Экспортировать все ресурсы namespace
kubectl get all,cm,secret,pvc -n loki-stack -o yaml > loki-stack-dump.yaml

# Проверить что применено из Helm
helm get values loki -n loki-stack
helm get manifest loki -n loki-stack
```

### Тестирование Loki API
```bash
# Проверка здоровья
curl -s http://localhost:3100/ready
curl -s http://localhost:3100/metrics | grep up

# Проверка конфигурации
curl -s http://localhost:3100/config

# Отправка тестового лога
curl -X POST http://localhost:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -d '{
    "streams": [{
      "stream": {"job": "test", "level": "info"},
      "values": [["'$(date +%s)000000000'", "test log message"]]
    }]
  }'
```

## Когда обращаться за помощью

Если проблема не решается:

1. Соберите информацию:
   - Вывод `kubectl describe pod <problem-pod> -n loki-stack`
   - Логи проблемного компонента
   - События: `kubectl get events -n loki-stack`
   - Версии: `helm list -n loki-stack`

2. Проверьте:
   - Есть ли похожие issues на GitHub Loki/Promtail
   - Документацию Grafana Loki
   - Yandex Cloud статус (для Managed K8s)

3. Создайте подробное описание проблемы с шагами воспроизведения