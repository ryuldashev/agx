# Экран артефактов — план

Статус: ✅ реализовано 2026-09-18 по рекомендуемым дефолтам (Руслан: «не знаю как ответить, но хочу
начать» → открытые вопросы решены как рекомендовано, см. конец). Дата плана: 2026-09-18.
Ход работ и отклонения от плана — `docs/log/2026-09-18-artifacts-screen.md`.

## Боль и сценарии

**Слова Руслана (15.09):** «вот такие все файлы-артефакты я их теряю и мне потом вытаскивать их
тяжело. кажется в agx должен быть экран артефактов где я бы видел ауткамы и мог к ним быстро
возвращаться без ллм».

Живой пример (проверен по транскриптам `~/.claude/projects/-Users-rus-mars-ceo-valuation/`):
за две сессии 14–18.09 в `~/mars/ceo/valuation/upside/v2/doc/` родились `report.pdf` (576k),
`short.pdf`, `brief.pdf`, `pitch.pdf`. Каждый агент показывал через `open …pdf` (7 вызовов `open`
на эту папку), окно Preview закрывалось — путь остаётся только в переписке с агентом. В той же
папке 20+ файлов-полуфабрикатов (`*.html`, `*.rendered.md`, `*.j2`, `build_doc.py.bak-*`) — их
показывать НЕ надо.

Сценарии:
1. **«Где тот PDF?»** — открыть экран, найти по имени/воркспейсу, двойной клик → Preview. Без агента.
2. **«Что мне сегодня показали?»** — список за день по всем сессиям, свежее сверху.
3. **«Вернуться к сессии, которая это сделала»** — из строки перейти в сессию (если ещё открыта).
4. **«Отправить партнёру»** — Reveal in Finder / Copy path → дальше руками.

## Источник данных — что проверил и что выбрал

Проверял по факту на транскриптах за 14 дней (582 файла в `~/.claude/projects/`, всего там 2486
файлов / 5 ГБ) и на живом примере.

| Кандидат | Что даёт | Цена | Ложные срабатывания | Вердикт |
|---|---|---|---|---|
| (а) транскрипты `~/.claude/projects/*/*.jsonl` | всё прошлое: `tool_use` Bash/Write с путями, время, cwd | парсинг 5 ГБ один раз (минуты), дальше инкрементально; Codex-транскрипты — другой формат | те же, что у хука, зависит от правила отбора | **берём для бэкфилла** (разово + «доскан» по mtime), не как живой источник |
| (б) хук `PostToolUse` → реестр | живой поток, есть `cwd`, `session_id`, `transcript_path`, полный `tool_input` | +1 хук на каждый Bash (bash-фильтр ~5 мс, python3 только при совпадении) ; ставится штатным Help ▸ Install Agent Status Hooks | нет, если правило отбора точное (ниже) | **основной источник** |
| (в) перехват `open` в шелле (функция/шим в PATH) | ловит любого агента (Codex, Hermes) и ручной `open` | шим `open` в PATH раньше `/usr/bin/open` — хрупко (флаги `-a`, `-R`, URL), PATH GUI-шеллов непредсказуем, ломает чужие скрипты | ручные `open` каталогов/приложений | **нет** в v1; вернуться, если понадобится Codex |
| (г) mtime-скан cwd сессии | ничего не пропустит | на живом примере в `doc/` 24 файла, из них артефакты — 4 (`*.pdf`); нужны правила исключений под каждый проект | `.html`, `.rendered.md`, `.j2`, `.bak-*`, `__pycache__` — 80 % шума | **нет** как источник; возможно позже как ручное «добавить из папки» |

**Правило отбора (что считаем артефактом):** файл, который агент **показал** Руслану, а не
просто записал. Это ровно то, что уже требует глобальный CLAUDE.md («любой готовый артефакт —
сразу `open <файл>`»). Сигналы, все — из `tool_input` Bash / tool_use:

1. `open <path…>` в команде Bash (в т.ч. `open -a Preview x.pdf`, цепочки `cd … && open x`,
   несколько файлов) — за 14 дней 419 вызовов, на живом примере все 4 PDF попали, ни один
   полуфабрикат — нет. URL (`open https://…`) — тоже артефакт (`kind: url`).
2. `agx reader <path.md>` — план/отчёт, показанный в панели.
3. `SendUserFile` (файл, отправленный в телефон).
4. Явная регистрация агентом: `agx artifact add <path> [--title …]` — для случаев, когда показ
   был иначе (Telegram, `tg send --photo`). Одна строка в `agx context`, чтобы агенты знали.

**Что сознательно не считаем:** `Write`/`Edit` (103 `.md`, 75 `.py`, 56 `.swift` за 14 дней —
это код и черновики, не ауткамы; PDF/PNG вообще рождаются Bash-скриптами, не Write), любые
записи в `docs/log/`, скрипты сборки. Если окажется, что «показанного» мало — добавить Write
по белому списку расширений отдельным `--source write` без смены модели.

**Привязка к сессии agx.** Хук получает `AGTERM_SESSION_ID` из env панели (как статус-хук) —
приложение само подставляет имена воркспейса/сессии в момент записи. Для бэкфилла: транскрипт
`<uuid>.jsonl` ↔ сессия agx через `restoreCommand` (`claude --resume <uuid>`) в
`windows/*.json` и `recent-closed.json` — проверено: 18 из 19 живых сессий имеют такой pin,
сессия «◑ Оценка v2 — короткая версия и рассылка» ↔ `a3a8601b…` — та, что открывала
`pitch.pdf`. Транскрипт без pin'а → строка без сессии, с папкой проекта и первым промптом как
подписью.

**Codex/Hermes-сессии** в v1 не покрыты (у Codex нет tool-хуков, только `notify` по концу
хода). Путь для них — (в) или явный `agx artifact add`.

## Модель данных и индекс

Одна таблица, один файл: `<stateDir>/artifacts.json` (рядом с `scheduled.json`, тот же
`PersistenceStore`-паттерн, app-global — не per-window). Владелец — приложение (`ArtifactIndex`
в `agtermCore`, host-free, тестируется без хоста). Ключ дедупликации — абсолютный путь (для URL —
строка): повторный `open` того же файла не плодит строк, а двигает `lastSeen` и `count`.

```swift
struct Artifact: Codable, Identifiable, Sendable {
    let id: UUID
    let path: String          // абсолютный путь или URL
    let kind: Kind            // file | url
    var title: String?        // подпись от агента (--title); иначе basename
    let firstSeen: Date
    var lastSeen: Date
    var count: Int            // сколько раз показывали
    var source: Source        // open | reader | sendfile | manual | backfill
    var sessionID: UUID?      // сессия agx, если известна (жива или в recent-closed)
    var sessionName: String   // имя на момент записи — заморожено, сессия может умереть
    var workspaceName: String
    var cwd: String           // откуда показали
    var agentSession: String? // uuid транскрипта Claude — «вернуться к переписке»
    var pinned: Bool
    var hidden: Bool          // «скрыть» = не удалять, а спрятать; файл не трогаем
}
```

Размер, mtime и «файл существует» **не храним** — читаем с диска при показе (PDF
перегенерируется, старая запись остаётся верной). Пропавший файл — строка гаснет, не исчезает.

Лимит: последние 2000 записей (скрытые и старые вытесняются первыми, закреплённые — никогда).

Живой поток: хук `agx-artifacts.sh` (в `Resources/agent-status/`, ставится тем же
Help ▸ Install Agent Status Hooks с marker-guard, `PostToolUse` c matcher `Bash|SendUserFile`)
→ `agtermctl artifact add <path> --source open --cwd … --agent-session <uuid>` → сокет →
`ArtifactIndex.record`. Хук молчит и всегда exit 0, вне agx — no-op (как статус-хук).

Бэкфилл: `scripts/agx-artifacts-backfill.py` — проходит `~/.claude/projects/*/*.jsonl`
(по умолчанию 30 дней по mtime, `--all` для всей истории), тем же правилом отбора, шлёт
`artifact add --source backfill --seen <iso>`; сессию agx подбирает по `restoreCommand`.
Запускается один раз руками после деплоя (и при желании — из палитры «Artifacts: rescan
transcripts»). Идемпотентен (дедуп по пути + время).

## UI

**Отдельное окно «Artifacts»** (SwiftUI `Window` scene, как Settings), а не оверлей поверх
терминала: список хочется держать открытым рядом с сессией, тянуть из него файлы в Finder/
Telegram, и он не должен воевать с dashboard/quick terminal за слот оверлея. Точки входа:
- built-in action `show_artifacts` → **⌘⇧A** (свободно, проверил `keymap list`), меню
  Window ▸ Artifacts, строка в command palette (⌃⇧P), `agtermctl artifact show`.
- Титлбар/сайдбар не трогаем (правило репо: новый chrome-элемент — только с одобрения).

Экран — `Table` с сортировкой по колонкам:

| Колонка | Что |
|---|---|
| иконка + имя | системная иконка типа (`NSWorkspace.icon(forFile:)`), `title` или basename; пропавший файл — серый + «missing» |
| тип | расширение / `url` |
| где | `workspace › session` (замороженные имена); если сессия жива — кликабельно → `session select` |
| когда | `lastSeen` относительно («2 ч назад», «вчера 19:12») |
| размер | с диска, пусто для URL/пропавших |
| 📌 | закреплённые — всегда сверху |

Над таблицей: поле поиска (по имени, пути, workspace, session), фильтр workspace
(picker), фильтр типа (pdf / изображения / документы / url / все), переключатель «показать
скрытые». Сортировка по умолчанию — `lastSeen` desc.

Действия (контекстное меню + клавиши, все без агента):
- **Open** — двойной клик / ⏎ (`NSWorkspace.open`, системное приложение; URL — браузер).
- **Quick Look** — пробел (`QLPreviewPanel`).
- **Reveal in Finder** — ⌘R (`activateFileViewerSelecting`).
- **Copy path** — ⌘C.
- **Pin / Unpin** — из контекстного меню (клавишу не занимаем).
- **Hide** — ⌫ (прячет строку, файл не трогаем; «показать скрытые» возвращает; Unhide там же).
- **Go to session** — если сессия открыта.
Drag строки наружу отдаёт `file URL` (перетащить в Telegram/Finder).

Визуальный язык — тот же, что у Settings/палитры: системные шрифты, chrome-цвета окна,
без своего стайлинга. Пустое состояние — одна строка: «Пока пусто. Артефакт — это файл,
который агент открыл через `open`, `agx reader` или `agx artifact add`.»

## Control API / agtermctl

Control-native по правилу репо (protocol → dispatcher → CLI → tests):

```
artifact.add     <path> [--title T] [--source open|reader|sendfile|manual|backfill]
                 [--session <id>] [--cwd P] [--agent-session <uuid>] [--seen <iso>]
                 → {id, path, deduplicated: bool}
artifact.list    [--workspace W] [--session S] [--kind K] [--hidden] [--limit N] [--json]
artifact.remove  <id|path>            (удалить запись из индекса; файл не трогаем)
artifact.pin     <id|path> [--off]
artifact.hide    <id|path> [--off]
artifact.open    <id|path>            (то же, что двойной клик — для скриптов)
artifact.show                         (открыть/поднять окно)
```

Read-back: `artifact.list`; верхний уровень `tree` не трогаем (индекс не часть дерева
сессий). События: `artifact.added` в `agtermctl events` (чтобы окно и HUD могли реагировать).
Обёртки в `scripts/agx`: `agx artifact add <path> [--title …]` (сессия и cwd — из env панели),
`agx artifact list`. Строка в `agx context`: «показал файл не через `open` — зарегистрируй
`agx artifact add`».

Синхронизируемые поверхности (правило репо): `site/commands.html`, `site/docs.html`,
`plugins/agterm/skills/agterm/{SKILL,reference}.md`, `.claude/rules/control-api.md`, FORK.md.

## Этапы реализации

Worktree от `origin/master` (main checkout сейчас на `hud-reveal-2026-09-16`, 3 коммита позади).

1. **Core (host-free):** `Artifact`, `ArtifactIndex` (load/save/record с дедупом/pin/hide/prune),
   `ArtifactSource`, `ControlDispatcher+Artifact.swift` (валидация: абсолютный путь или URL,
   без control chars, title ≤ 200), `Command.artifact*`, `ControlActions`, тесты dispatcher +
   protocol round-trip + index.
2. **App:** `ControlServer+Artifact.swift` (резолв сессии → имена, событие), `ArtifactsWindow`
   (Table + фильтры + действия + Quick Look), `BuiltinAction.showArtifacts` + меню + палитра +
   `actions.openArtifacts`. Хостed-тесты: окно строится, действия над фикстурой.
3. **CLI + хук:** `ArtifactCommands.swift` в `agtermctlKit`, `agx artifact …`, `agx context`
   строка, `Resources/agent-status/agx-artifacts.sh` + запись в `AgentHooksInstall.claudeHooks`
   (тест на merge), `scripts/agx-artifacts-backfill.py`.
4. **Docs/surfaces:** commands.html, docs.html, skill, control-api.md, FORK.md, `docs/log/`.
5. **Гейты и деплой:** `make build`, `swift test`, `make test-app`, `make lint`, целевой
   XCUITest (`ArtifactsUITests`: add через сокет → окно показывает строку → `artifact list`).
   Коммит + `make deploy` без переспроса (правило CLAUDE.md), перезапуск — за Русланом.
   Затем Help ▸ Install Agent Status Hooks (из Release) и `agx-artifacts-backfill.py`.

**Проверка «готово»:** после перезапуска ⌘⇧A показывает `pitch.pdf` из
`~/mars/ceo/valuation/upside/v2/doc/` (бэкфилл) с сессией «◑ Оценка v2 — короткая версия и
рассылка», двойной клик открывает Preview; новый `open x.pdf` из любой Claude-сессии в agx
появляется в окне без перезапуска.

## Что НЕ делаем в v1

- Никакого ИИ: ни описаний, ни тегов, ни «похожих». Подпись — только та, что дал агент явно.
- Не сканируем папки по mtime и не индексируем `Write`/`Edit` — 80 % было бы шумом.
- Не трогаем файлы: нет удаления с диска, нет переименований, нет копий в свою папку.
- Не показываем превью-содержимое внутри окна (Quick Look этим занимается).
- Не покрываем Codex/Hermes-сессии автоматически (нет tool-хуков) — только `agx artifact add`.
- Не добавляем кнопку в титлбар/сайдбар и не делаем per-window индексов.
- Не делаем экспорт/шаринг (Telegram и т.п.) — Reveal in Finder / drag достаточно.

## Открытые вопросы — решены дефолтами (2026-09-18)

1. Только «показанное». 2. Окно. 3. 30 дней (`--all` есть). 4. Скрыть в UI, `remove` в CLI и в контекстном меню.

### Как были поставлены

1. **Объём сигналов:** только «показанное» (`open` / `agx reader` / `SendUserFile` / явный
   `add`) — или сразу добавить `Write` по белому списку (`.pdf .html .png .docx .xlsx .pptx`)?
   Рекомендую первое: точность важнее полноты, добавить второе — один флаг.
2. **Окно или оверлей?** Рекомендую окно (⌘⇧A) — можно держать рядом и таскать из него файлы.
3. **Бэкфилл:** 30 дней по умолчанию или вся история (5 ГБ, минуты, один раз)?
4. **Скрыть vs удалить:** предлагаю только «скрыть» (обратимо) + `artifact remove` в CLI.
