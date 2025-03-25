**ДОМАШНЕЕ ЗАДАНИЕ ПО DEPLOYMENT**

- Манифест namespace.yaml такой же как в предыдущий домашке применяется командой `kubectl apply -f namespace.yaml`
  <img width="1092" alt="Screenshot 2025-03-25 at 21 50 30" src="https://github.com/user-attachments/assets/e4307bb7-a3ca-49c3-8dc0-604af05a7713" />
  
- Создал новый манифест deployment.yaml с использованием логики предыдущего задания, запуск `kubectl apply -f deploymant.yaml`
  <img width="1095" alt="Screenshot 2025-03-25 at 22 03 49" src="https://github.com/user-attachments/assets/92d999ef-b922-40be-b27f-40e4966e8e85" />
  
- Также проверил работоспособность контейнера внутри подов - и доступность страницы на localhost:8000, не забываем пробросить порт `kubectl port-forward pod/podname 8000:8000 -n homework`
  <img width="1093" alt="Screenshot 2025-03-25 at 22 06 03" src="https://github.com/user-attachments/assets/5df4b456-e45d-4cec-be8e-ab318254ffb9" />
  <img width="632" alt="Screenshot 2025-03-25 at 22 05 46" src="https://github.com/user-attachments/assets/f500a37d-ef2f-4806-9e62-1e3391a0c103" />
  
- Также проверил как работает Readness probe - переименовал файл index.html -> index_test.html. При этой контейнер работает как и ожидалось
  <img width="1089" alt="Screenshot 2025-03-25 at 22 47 42" src="https://github.com/user-attachments/assets/fb0246cd-9f40-40eb-87c6-80091fa6dd20" />
  <img width="994" alt="Screenshot 2025-03-25 at 22 49 36" src="https://github.com/user-attachments/assets/d5c99d14-c004-4ec3-ab27-a28edce44873" />


