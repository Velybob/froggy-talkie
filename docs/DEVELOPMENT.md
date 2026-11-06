# Разработка

Основные модули: `DictationApp` (SwiftUI/AppKit), `DictationCore` (ASR),
`DictationSystem` (хоткей, вставка, индикатор), `DictationModels` (установка весов).
GUI не зависит от `WhisperEngine`. Зависимости закреплены: FluidAudio 0.18.2,
Argmax OSS/WhisperKit 1.1.1; точные commit ID — в `Package.resolved`.

## Проверка интерфейса без записи

После release-сборки:

```sh
swiftc -swift-version 6 -parse-as-library Sources/DictationApp/DictationViews.swift \
  Sources/DictationApp/ShortcutEditor.swift Sources/DictationApp/RecordingOverlay.swift \
  scripts/render_ui.swift -I .build/release/Modules \
  .build/release/DictationSystem.build/*.o \
  -o /tmp/froggy-render-ui -module-cache-path .cache/clang
/tmp/froggy-render-ui /tmp/froggy-ui
swiftc -swift-version 6 -parse-as-library Sources/DictationApp/DictationViews.swift \
  Sources/DictationApp/ShortcutEditor.swift Sources/DictationApp/RecordingOverlay.swift \
  scripts/check_appearance.swift -I .build/release/Modules \
  .build/release/DictationSystem.build/*.o \
  -o /tmp/froggy-check-appearance -module-cache-path .cache/clang
/tmp/froggy-check-appearance
```

Рендер создаёт заданные состояния обеих тем, включая настройки и загрузку
модели. Проверка оформления использует AppKit-хосты без видимых окон. Они не
создают DictationModel, не включают микрофон, не меняют preferences и не
подтверждают фактическую работу записи/вставки. Системное переключение темы
macOS на работающем приложении проверяется отдельно.

Иконка `Assets/AppIcon.png` — утверждённый оригинал. `build_app_icon.sh` вызывает
`render_app_icon.swift`, создаёт скругление, прозрачные поля и ICNS. Новая
генерация изображения не требуется.

## Дополнительный asr-bench

`swift build -c release --product asr-bench` собирает инструмент сравнения
Parakeet и WhisperKit. Он не входит в архив GUI. Собственный manifest:

```json
{
  "dataset": "my-test-data",
  "revision": "1",
  "samples": [{"id": "sample-1", "language": "ru", "path": "sample.wav",
    "reference": "Тестовая фраза", "sha256": "SHA256_OF_AUDIO"}]
}
```

```sh
.build/release/asr-bench --models ./Models --manifest /path/to/manifest.json \
  --output /tmp/asr-results.json --compute ane --repeats 2
```

Результаты включают эталоны и распознанные тексты: не публикуйте приватные
записи, manifest и JSON с личными данными. Примеры аудио и исследовательские
корпуса не включены. Для WhisperKit потребуется отдельно подготовленная папка
`whisper-turbo` и `whisper-tokenizer` согласно `WhisperRecognizer.swift`; автоматическая
загрузка через benchmark не поддерживается. Сравнительные модели не нужны GUI.

## Локальная установленная копия

В исходной исследовательской рабочей папке остаётся отдельный
`scripts/package_app.sh` для локального сертификата и замены `dist/`. Этот
процесс не входит в публичный экспорт. Для подготовки внешнего кандидата
используйте только `build_release.sh`. Не пересобирайте и не перезапускайте
работающую копию без сохранения актуального текста и проверки отсутствия записи.


## Вставка в приложения Electron/Chromium

`TextFocusResolver` сначала проверяет активное поле, затем при необходимости
запрашивает `AXManualAccessibility` / поддерживаемый `AXEnhancedUserInterface`
и повторяет проверку с паузами 50, 100 и 200 мс. Исходный PID фиксируется при
нажатии хоткея. Используются только ссылки на фактический фокус приложения,
системы или активного окна, без поиска произвольного поля и без чтения текста.
Перед вставкой снова проверяются поле, приложение, выделение и защищённый ввод.

Основания для включения дерева:
- https://www.electronjs.org/docs/latest/tutorial/accessibility#macos
- https://www.chromium.org/developers/design-documents/accessibility/

Тесты `TextFocusResolverTests` используют изолированный адаптер: отложенная
готовность дерева, смена приложения, парольное поле, отмена и недоступный редактор.
Они не подтверждают вставку в конкретную версию Codex или Time: это нужно
проверять вручную на целевом Mac.
