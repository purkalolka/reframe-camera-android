# Release v1.0.0

Релиз первой версии **reFrame Camera** — порт reFrame с эффектом дисплея ePaper (Waveshare Spectra 6) на Android.

**Артефакт:** `app-release.apk` (устанавливается sideload-установкой). Android 5.0 (API 21) и выше.

## Что внутри
- **Камера** — фронтальная/задняя, вспышка, импорт любого фото из галереи.
- **Брендинг** — reFrame // SPECTRA6, фиксированный в портретной ориентации.
- **Палитра Blended Spectra-6** — 6 цветов e-ink, смешивание насыщенных и ненасыщенных чернил, предотвращение зелёного сдвига.
- **Дизеринг** — Floyd-Steinberg (с гашением ошибки, без выгорания белого) или Bayer 4x4 (dE2 в CIELAB)
- **Анимация ePaper Refresh** — физически достоверная симуляция переполюсовки микрокапсул, настраиваемая 1.5-6.0 c
- **Настройки** — плотность/зернистость, контраст, boost, палитры, скорость обновления; всё сохраняется между запусками

## Известные особенности

- APK подписан debug-ключом (для sideloading). Для публикации в Google Play нужен собственный релизный ключ.

## Changelog — v1.0.0

- a95d348 feat: Настраиваемая длительность ePaper-refresh + SharedPreferences + аудит качества
- 2351b97 feat(epaper): ритейл-ESL пиксель-чанк флип refresh-симуляции
- c2621de feat(animation): дискретный ePaper/ESL refresh-цикл (polarity flashes, pigment waves)
- 8cce985 refactor(ui): убрать дублирующую кнопку настроек в топ-баре
- 3e04fdd fix(orientation): 180-degree flip landscape photos, brand static
- c2bd0a1 fix(orientation): инверсия знака акселерометра (correct icon/photo rotation)
- 27f2c50 feat(camera): portrait-up lock, акселерометр, hardware orientation → картинка
- 3360627 feat(orientation): landscape/portrait support, correct photo rotation
- aaa04de fix(camera): preview aspect ratio, mirror front camera (preview + capture)
- 9171c7e feat(settings): density/grain, palette presets, contrast/saturation
- 3bd3cdb fix(dithering): white blowout (CIELAB LUT + error damping)
- 9d03cee fix(dither): Floyd-Steinberg rewrite, perceptual color matching
- a0ef1d5 fix(res): adaptive icon strictly in mipmap-anydpi-v26
- b48d99b fix(res): app icons + mipmap resources
- 55fc8b4 fix(deps): gal -> image_gallery_saver_plus, compileSdk 35
- d1433a6 fix(android): AndroidX + declarative Flutter Gradle plugins
- b734272 fix(ci): invalid flag in flutter build apk
- 53cf38e feat: initial reframe camera app