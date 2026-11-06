# Подготовка и распространение

Документ проверен по официальной документации Apple 6 ноября 2026 года.
Текущий предварительный выпуск: **v0.5.0-beta.2**, версия 0.5.0, сборка 17.
Публичный репозиторий: [Velybob/froggy-talkie](https://github.com/Velybob/froggy-talkie).
[v0.5.0-beta.2](https://github.com/Velybob/froggy-talkie/releases/tag/v0.5.0-beta.2)
распространяется как prerelease для проверки на другом Mac. Сборка `preview`
подписана ad-hoc и не нотарифицирована.

## Чистый комплект исходников

```sh
python3 scripts/export_source.py
```

Результаты: `release/0.5.0/FroggyTalkie-source`, ZIP исходников и SHA-256.
Экспорт использует явный список файлов, включает MIT, иконку, исходники,
тесты, лицензии, документацию и скрипты сборки. Он не копирует `research`,
`output`, модели, локальные зеркала, кеши, сертификат разработчика, Keychain,
записи, журналы и Git-историю. `SOURCE_MANIFEST.json` фиксирует SHA-256 каждого
включённого файла. Не заменяйте экспорт командой `git add .` из исследовательского
родительского каталога.

Для проверки на чистом пути распакуйте source ZIP в новый каталог вне рабочей
копии, выполните `zsh scripts/build_release.sh`, затем `swift test` с параметрами
из README. Сборка должна получать закреплённые зависимости по публичным URL;
личное зеркало FluidAudio и исследовательские скрипты не нужны.

```sh
python3 scripts/check_distribution.py release/0.5.0/FroggyTalkie-source \
  release/0.5.0/Froggy-Talkie-0.5.0-macos-arm64-preview.zip
```

Это проверка заданных признаков, а не доказательство отсутствия любых секретов.
Перед публикацией дополнительно просмотрите состав исходников и ZIP.

## Подпись

`zsh scripts/build_release.sh` создаёт отдельную ad-hoc сборку с Hardened Runtime
и минимальным разрешением Audio Input. Приложение не использует App Sandbox,
поскольку вставка работает через Accessibility. `get-task-allow`, отключение
library validation и разрешение unsigned executable memory не добавляются.

При наличии собственного **Developer ID Application** можно подготовить
подписанный кандидат в другой папке:

```sh
zsh scripts/build_release.sh --output ./release/developer-id \
  --identity 'Developer ID Application: YOUR NAME (TEAMID)'
```

Локальный самоподписанный сертификат и Apple Development не заменяют Developer
ID для этого процесса. Приватные ключи остаются в Keychain. Скрипт не создаёт
сертификаты, не экспортирует ключи, не меняет доверие и ничего не отправляет
на нотарификацию. Для Developer ID используется secure timestamp.

## Нотарификация — только после отдельного разрешения на загрузку

Этот этап отправляет приложение Apple и здесь автоматически не выполняется.
Потребуются членство Apple Developer Program и соответствующие учётные данные.
Сохраните их отдельно через `notarytool store-credentials`; не помещайте пароли,
API-ключи или сертификаты `.p12` в исходники и команды с видимыми секретами.

```sh
# ARCHIVE — ZIP, созданный сборкой с Developer ID.
# APP — соответствующий подписанный Froggy Talkie.app.
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$PROFILE" --wait
# Продолжать только после Accepted; проверить log по ID, если есть ошибки.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute --verbose=4 "$APP"
# Создать новый ZIP после stapling. Не менять подписанные ресурсы.
ditto -c -k --keepParent "$APP" Froggy-Talkie-0.5.0-macos-arm64.zip
shasum -a 256 Froggy-Talkie-0.5.0-macos-arm64.zip
```

`build-info.json` отражает состояние на этапе сборки (до нотарификации).
Не редактируйте его внутри уже подписанного приложения: финальный результат
нотарификации фиксируется отдельно в журнале выпуска. ZIP нельзя staple
напрямую; ticket прикрепляется к `.app`, после чего ZIP создаётся заново.

Перед стабильным выпуском проверьте именно скачанный архив на отдельном Mac/чистой учётной
записи: запуск с quarantine, загрузку модели, микрофон, хоткей, вставку, отмену,
обновление и системную тему. Подписанный и нотарифицированный файл всё равно
может показать стандартный диалог первого запуска и запросы разрешений.

Источники Apple:
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input
- https://support.apple.com/102445
