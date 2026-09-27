# reFrame Camera for Android

Порт экспериментальной камеры **reFrame** (на основе дисплея Waveshare Spectra 6 ePaper) на Android.

> Оригинальный проект: [reframe.camera](https://reframe.camera) | [GitHub reframe](https://github.com/kaloyaan/reframe)

---

## ✨ Что реализовано

1. **Точный алгоритм обработки Spectra 6 ePaper**:
   - Палитра **Blended Spectra-6** (смешивание насыщенных и ненасыщенных чернил: Black, White, Red, Green, Blue, Yellow с фактором $0.6$).
   - Коррекция яркости ($\times 1.1$) и сочности цвета ($\times 1.4$).
   - Полноценный **Floyd-Steinberg Error Diffusion** дизеринг.
   - Альтернативный **Ordered Bayer Dithering (матрица 4x4)** с расчетом дистанций в цветовом пространстве **CIELAB ($\Delta E^2$)**, предотвращающий смешивание серых тонов в зелёный.
2. **Анимация проявления «ePaper Refresh»**:
   - Симуляция физической переполюсовки микрокапсул электронных чернил (мерцание, фазы очистки и прорисовка волны цветных пигментов).
3. **Видоискатель и функции**:
   - Обычный видоискатель камеры с возможностью переключения передней/задней камеры и вспышки.
   - Возможность импортировать **любое фото из галереи** телефона и применить эффект reFrame.
   - Сохранение полученного изображения в галерею смартфона (в альбом `reFrame`).
   - Кнопка «Поделиться» (Share).
   - Вычисления дизеринга выполняются в отдельном фоновом изоляте (UI не подвисает).
4. **Онлайн-компиляция (GitHub Actions)**:
   - В репозитории уже настроен рабочий воркфлоу `.github/workflows/build-apk.yml`.
   - При любом пуше в GitHub компилируется готовый **`app-release.apk`**, доступный для скачивания прямо со страницы Actions.

---

## 🚀 Как запустить онлайн-сборку (получить APK без Android Studio)

1. Создайте новый репозиторий на GitHub (например, `reframe-camera-android`).
2. В этой папке выполните:
   ```bash
   git init
   git add .
   git commit -m "feat: initial reframe camera app"
   git branch -M main
   git remote add origin https://github.com/ВАШ_АККАУНТ/reframe-camera-android.git
   git push -u origin main
   ```
3. Перейдите во вкладку **Actions** в вашем репозитории на GitHub:
   - Автоматически запустится сборка **Build Android APK**.
   - Через 2–3 минуты в разделе **Artifacts** появится файл `reframe-camera-release-apk` со свежим `app-release.apk`.
   - Скачайте и установите на телефон!
