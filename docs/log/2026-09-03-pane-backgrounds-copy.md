# 2026-09-03 — фон по панелям, чистое копирование, кликабельный `file:line`

Состояние: смержено в `master` (`0c58ccb`), запушено, `/Applications/agx.app` задеплоен и
перезапущен пользователем. Ветка `pane-backgrounds-copy-2026-09-03` осталась на origin.

## Откуда пришло
Правая (split) панель выглядела «плоской»: глобальный `background-image` из
`~/.config/ghostty/config` стоит с `fit = none` + `position = bottom-right`, то есть каждая
поверхность якорит один и тот же фикс-размер 720×720 в свой угол. В узкой панели видно только
правый срез картинки, а он почти пустой. Плюс просьба: «поведение мышки и выделения как в
прокачанном мессенджере».

## Что сделано

**Фон по панелям.** `PaneBackgroundStyle` (mirror + fade) в ядре, `Position.horizontallyMirrored`,
`WatermarkConfig.inheritedImageOverlayText` — оверлей, который переопределяет ТОЛЬКО
`background-image*`, не трогая `background-opacity` (её владелец — базовый конфиг, иначе в панель
запекается прозрачность окна). Зеркальный PNG рисует `WatermarkRenderer.mirroredCopy` (CoreGraphics
flip), кэш `watermarks/mirror-<FNV1a от path+mtime>.png` — `Hasher` нельзя, его сид рандомен на
процесс. Настройка Appearance, **по умолчанию включена**, сила 50%.

**Умное копирование.** `CopyCleanup.clean` снимает рамочный гуттер (`│`, `┃`, `>` …), хвостовые
пробелы, пустые строки по краям и общий отступ — гуттер только если он есть у ВСЕХ непустых строк,
поэтому `ls | wc -l` не трогается. Перехват в `copy(_:)` и в `keyDown` по физической клавише C
(бинды `super+key_c` из `ghostty-defaults.conf` идут мимо Swift, на кириллице иначе не поймать), и
в `mouseUp` — там ghostty уже положил сырой текст своим copy-on-select, мы перекладываем чистый.

**Флеш «Copied».** `CopyFlashView` — layer-backed NSView у курсора, 90/700/220 мс, `hitTest → nil`,
хвост через `perform(_:afterDelay:)` (cancellable; `asyncAfter` не прошёл Swift 6 Sendable).

**`file.swift:120` по клику.** Дефолтный regex ghostty его уже ловил и слал `GHOSTTY_ACTION_OPEN_URL`;
ломался наш `LinkPolicy`, который игнорировал всё без схемы. Добавлен `LinkPolicy.fileReference`
(чистый разбор пути и строки) + `ConfigPaths.editorCommand(forPath:line:)` с `+N`.

## Гоучи (не выводится из кода)
- `copy-on-select` в agx уже работал: ghostty на macOS по умолчанию `true`, agterm ставит
  `supports_selection_clipboard = true`, а `writeClipboard` игнорирует location и пишет в
  `NSPasteboard.general`. То есть «выделил → ⌘V» было и до этой сессии.
- `ghostty_config_get` умеет читать `background-image` (тип `Path` имеет `cval()` → `ghostty_config_path_s`)
  и enum-ключи как tag-строки. Так `baseBackgroundImage` берётся из resolved-конфига, а не парсингом файлов.
- `fit: .none` в Swift — это `Optional.none`, а не `Fit.none`. Тест молча получал `contain`.
- `GHOSTTY_ACTION_SELECTION_CHANGED` в ghostty.h есть, но в agx не обработан — если понадобится
  реагировать на выделение без mouseUp, вот точка входа.

## Что дальше
- Зеркало — первый шаг «умной работы с фонами панелей». Следующее по объёму: сделать фон
  pane-scoped и в control API (сейчас `session.background` один спек на все три поверхности).
- Разное поведение материала панелей (правая на 2–3% светлее) — обсуждалось, не делалось.
- `make test-app` в этой сессии не гонялся (долгий), UI-тестов на новые пути нет.
