# Helm Charts для Loki Stack

## Структура

- `values-loki.yaml` - основные настройки для Loki и Promtail
- `values-prometheus.yaml` - настройки для Prometheus Stack
- `values-loki-s3-override.yaml` - шаблон для S3 credentials (не коммитить!)

## Использование

1. Скрипты автоматически скачают нужные чарты:
   - Loki из Yandex Marketplace или Grafana
   - kube-prometheus-stack из prometheus-community

2. S3 credentials подставляются автоматически из `outputs/loki-s3-key.json`

3. Все компоненты размещаются на нодах с label `node-role=infra`

## Настройка

### Изменение nodeSelector

В файлах `values-*.yaml` измените секцию `nodeSelector`:

```yaml
nodeSelector:
  your-label: your-value