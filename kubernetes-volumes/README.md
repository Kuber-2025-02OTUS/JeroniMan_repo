# ДОМАШНЕЕ ЗАДАНИЕ ПО VOLUMES

## Выполненные задачи

### Основное задание

1. **Создан PersistentVolumeClaim (pvc.yaml)**
   - Запрашивает 1Gi хранилища
   - AccessMode: ReadWriteOnce
   - Использует StorageClass по умолчанию (изменено в задании со *)

2. **Создан ConfigMap (cm.yaml)**
   - Содержит произвольные пары ключ-значение
   - Файлы: app.properties, database.conf, welcome.txt, info.json

3. **Обновлен deployment.yaml**
   - Volume типа emptyDir заменен на PVC
   - Добавлено монтирование ConfigMap в /homework/conf
   - Данные теперь персистентные между перезапусками подов

### Задание со звездочкой (*)

1. **Создан StorageClass (storageClass.yaml)**
   - Provisioner: k8s.io/minikube-hostpath
   - ReclaimPolicy: Retain (PV сохраняется после удаления PVC)

2. **Обновлен PVC**
   - Теперь использует созданный StorageClass: homework-storage

## Применение манифестов

```bash
# Применяем namespace
kubectl apply -f namespace.yaml

# Метим ноду для nodeSelector
kubectl label nodes minikube homework=true

# Создаем StorageClass
kubectl apply -f storageClass.yaml

# Создаем PVC
kubectl apply -f pvc.yaml

# Создаем ConfigMap
kubectl apply -f cm.yaml

# Применяем Deployment
kubectl apply -f deployment.yaml

# Применяем Service
kubectl apply -f service.yaml
```

## Проверка работоспособности

### 1. Проверка создания ресурсов
```bash
kubectl get all,pvc,cm,storageclass -n homework
```

### 2. Проверка доступности веб-сервера
```bash
kubectl port-forward deployment/webserver-deployment 8000:8000 -n homework
```

### 3. Проверка контента
- Основная страница: http://localhost:8000/
- ConfigMap файлы: http://localhost:8000/conf/
  - http://localhost:8000/conf/app.properties
  - http://localhost:8000/conf/database.conf
  - http://localhost:8000/conf/welcome.txt
  - http://localhost:8000/conf/info.json

### 4. Проверка персистентности данных
```bash
# Удаляем все поды
kubectl delete pods -l app=webserver -n homework

# Ждем пересоздания
kubectl get pods -n homework -w

# Проверяем, что данные сохранились
kubectl port-forward deployment/webserver-deployment 8000:8000 -n homework
curl http://localhost:8000/
```

## Скриншоты выполнения

<img width="1039" alt="Screenshot 2025-07-06 at 18 48 49" src="https://github.com/user-attachments/assets/dbbc98be-4a5c-4b57-8830-5e15cbfe7f96" />
<img width="1512" alt="Screenshot 2025-07-06 at 18 47 08" src="https://github.com/user-attachments/assets/4fff719b-1405-40f1-bf6a-24e0b03931bf" />
<img width="619" alt="Screenshot 2025-07-06 at 18 48 19" src="https://github.com/user-attachments/assets/0f83b6f1-d7ec-4166-9374-9ba5abd52abb" />
<img width="471" alt="Screenshot 2025-07-06 at 18 48 27" src="https://github.com/user-attachments/assets/8d944380-b4fe-4749-88c1-a82e727d467c" />


## Результат

- ✅ PVC успешно создан и примонтирован
- ✅ ConfigMap доступен по URL /conf/
- ✅ Данные сохраняются между перезапусками подов
- ✅ StorageClass с Retain policy работает корректно
