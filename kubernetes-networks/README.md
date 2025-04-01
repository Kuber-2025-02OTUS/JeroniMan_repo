**ДОМАШНЕЕ ЗАДАНИЕ ПО NETWORK**

- Создаем новую директорию, копируем в нее deployment.yaml и namespace.yaml
- Изменяем readiness пробу на проверку httpGet
- Создаем service.yaml который будет направлять трафик на поды
  <img width="643" alt="Screenshot 2025-04-01 at 21 42 26" src="https://github.com/user-attachments/assets/fa64bbac-5427-45f8-9751-74858e502292" />
- Далее создаем ingress.yml который описывает параметры для ingress-controller на базе nginx
  <img width="742" alt="Screenshot 2025-04-01 at 21 44 52" src="https://github.com/user-attachments/assets/876607fd-42c4-4cee-a363-41475770078a" />
- Тип контроллера пришлось поменять на LoadBalancer чтобы можно было создать тунель для него
  <img width="944" alt="Screenshot 2025-04-01 at 21 46 38" src="https://github.com/user-attachments/assets/c4d60809-5456-49f0-9835-fbb553449aa2" />
- По итогу - результат
  <img width="638" alt="Screenshot 2025-04-01 at 21 47 16" src="https://github.com/user-attachments/assets/bd4f7922-30d7-46f7-9b25-3f4d24f7815c" />
- Для задания со * нужно было добавить аннотацию `nginx.ingress.kubernetes.io/rewrite-target: /index.html`
