# 2026-09-03 — TCC: стабильная подпись + permission wall

Состояние: код готов, ядро и app-тесты зелёные, релизная сборка собирается и подписана
Developer ID. **НЕ задеплоено и не закоммичено** — в рабочем дереве параллельно идёт другая
сессия (watermark / split-pane background / copy-cleanup), файлы перемешаны.

## Проблема
agx по несколько раз в день просил доступы («agx would like to access Apple Music, your music
and video activity, and your media library»). Две независимые причины:

1. **Ad-hoc подпись.** TCC привязывает грант к designated requirement приложения; у ad-hoc
   бандла DR = `cdhash H"…"`. `make deploy` пересобирает и ставит новый бинарь → новый cdhash →
   для macOS это другое приложение → спрашивает всё заново. 2 сентября было 7 коммитов подряд,
   отсюда «три раза за день».
2. **Запрашивает не agx.** В исходниках нет ни MediaLibrary, ни Music API. Прос просит
   дочерний процесс панели (`find ~`, `du -sh ~/*`, mdfind), который заходит в
   `~/Music/Music/Music Library.musiclibrary`; macOS приписывает запрос ответственному
   GUI-приложению. Ровно тот же кластер грантов виден у `uz.marshub.mcode` (2026-07-16,
   Photos/MediaLibrary/Downloads/NetworkVolumes выданы секунда-в-секунду — один проход по home).

## Что сделано
- `scripts/build.sh`: резолвит `AGTERM_SIGN_IDENTITY` → keychain Developer ID → ad-hoc и
  передаёт `CODE_SIGN_IDENTITY` в xcodebuild. `project.yml`: пост-билд фаза больше не
  переподписывает ad-hoc, а берёт `${CODE_SIGN_IDENTITY:--}` (иначе финальный re-seal затирал бы
  подпись Xcode). Проверено: DR стал
  `anchor apple generic and identifier "uz.marshub.agx" … subject.OU = "84D4N2AA64"` —
  переживает пересборки. Замер стоимости: ad-hoc 0.13 с, Developer ID без timestamp 0.30 с,
  с `--timestamp` (сеть) 1.37 с; Xcode подписывает с `--timestamp=none`, так что +0.2 с на сборку.
- `agterm/Info.plist`: добавлены недостающие usage-строки — `NSAppleMusicUsageDescription`,
  Desktop/Documents/Downloads, FileProviderDomain, FocusStatus, Network/RemovableVolumes.
  Текст в стиле уже существующих: «Command-line tools you run inside agx … request … through agx»,
  то есть системный диалог сам объясняет, что просит команда в панели, а не терминал.
- `agtermCore/PermissionPrimer.swift` — host-free каталог областей, копирайтинг, due-решение,
  строки атрибуции (+ 8 тестов).
- `agterm/Permissions/PermissionProbe.swift` — поднимает НАСТОЯЩИЙ диалог macOS чтением
  защищённой директории (API запроса для файловых сервисов не существует), off-main.
- `agterm/Permissions/PermissionsAlert.swift` — стена разрешений: объяснение почему в диалоге
  написано «agx», чекбокс на область (Music/Photos/Desktop/Documents/Downloads), кнопки
  «открыть System Settings» для Full Disk Access / Accessibility / Screen Recording и кнопка
  **What's running now…** — список «workspace ▸ сессия — команда» по всем панелям. Диалог TCC
  замораживает процесс, который его вызвал, поэтому виновник в этом списке виден, пока диалог
  на экране (+ 5 hosted-тестов).
- Показывается один раз (`AppSettings.permissionsPrimerShown`), после welcome-алерта (не рядом —
  вложенный modal loop иначе стакается), и всегда доступна из Help ▸ Permissions….
- `agterm/AlertAccessoryLayout.swift` — indent аксессуара вынесен из `WelcomeAlert` (обе стены
  используют один расчёт).

## Дальше
1. Дождаться, пока сядет параллельная сессия, развести хунки в `AppSettings.swift` /
   `SettingsModel.swift` / `agtermApp.swift` и закоммитить отдельно.
2. `make deploy` + перезапуск app. **После смены подписи macOS один раз спросит доступы заново** —
   это ожидаемо, дальше гранты держатся.
3. Проверить живьём: Help ▸ Permissions…, «What's running now…» на панели с `du -sh ~/*`.
