FROM nginx:1.25-alpine

# Копируем кастомную конфигурацию nginx
COPY nginx.conf /etc/nginx/nginx.conf

# Проверяем конфигурацию
RUN nginx -t

# Открываем порты
EXPOSE 80 8080

# Запускаем nginx
CMD ["nginx", "-g", "daemon off;"]