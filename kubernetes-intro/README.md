**Домашнее задание 1**

- Установил Minikube на mac через brew (kubectl также установился)
- Запустил minikube `minikube start`
  <img width="1093" alt="Screenshot 2025-03-23 at 23 04 27" src="https://github.com/user-attachments/assets/77f878c1-60a2-44be-b935-931a369b9610" />
- Создал и применил манифест для нового namespace командой `kubectl apply -f namespace.yaml`
- Создал манифест и запустил новый под `kubectl apply -f pod.yaml`
- Дождался развертывания пода, пробросил порт и проверил работу вебсервера
`kubectl port-forward pod/<pod-name> 8000:8000 -n homework`
<img width="842" alt="Screenshot 2025-03-23 at 23 39 59" src="https://github.com/user-attachments/assets/13868319-fdac-4c96-aa45-fb9d44874c40" />

**РЕЗУЛЬТАТ**

<img width="657" alt="Screenshot 2025-03-23 at 23 40 06" src="https://github.com/user-attachments/assets/dab58dc6-38a4-4174-b94e-4bd01c7c6936" />
