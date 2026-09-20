# Онбординг AGX — первый запуск и первые шаги

Статус: черновик, пишется инкрементально (2026-09-12, ночь). Ветка `onboarding-2026-09-12`,
worktree от `26c9fd4` (agent-profiles — то, из чего собран задеплоенный v0.24.0; `origin/master`
на 10 коммитов старше и НЕ содержит reader/failover/agent-profiles — деплой с него откатил бы
приложение, поэтому «от origin/main» из брифа заменено на «от задеплоенного коммита». Решил сам).

Исследование (сырьё для этого плана): `docs/plans/research/{personal-layer,installers-audit,ui-patterns}.md`.

## 0. Что уже есть (чтобы не изобретать)

| элемент | где | что делает сегодня |
|---|---|---|
| Welcome-алерт | `agterm/WelcomeAlert.swift`, копия `agtermCore/FirstRunWelcome.swift` | NSAlert на первом запуске: две галочки (skill, hooks) → Install/Later. Показывается один раз (`welcomeShown` + `hasPriorState`). Текст ещё говорит «Welcome to agterm». |
| Стена разрешений | `agterm/Permissions/PermissionsAlert.swift`, `agtermCore/PermissionPrimer.swift` | Второй модал после welcome; 5 probe-областей (Music/Photos/Desktop/Documents/Downloads) + 3 «только в System Settings» (FDA, Accessibility, Screen Recording). Флаг `permissionsPrimerShown`. Help ▸ Permissions… |
| Три инсталлера | `CLIInstaller`, `AgentHooksInstaller` (generic по `agents/*/agent.json`), `SkillInstaller` | Help ▸ Install …; результат хуков — `AgentHooksResultView` (строки-агенты с тайлами) |
| Settings ▸ Agents | `Views/AgentsSettingsView.swift`, `AgentCatalog` | «Found on This Mac» + Connect |
| Гайд | worktree `guide-2026-09-12`, `docs/guide/{README,model,agents,driving,reader,keyboard,settings}.md` | «AGX in 5 minutes» + главы. Онбординг ссылается, не дублирует. |
| Шпаргалка ⌥ | `Views/OptionHints.swift`, `docs/ui-lexicon.md` | Панель токенов под титлбаром |
| Журнал действий | `<state>/journal.jsonl` (`ActionJournal`) | Каждый чорд/действие/мутирующий control-запрос — готовый источник для «что человек уже сделал» |

## 1. Граница «AGX vs личное Руслана»

Опыт Руслана = приложение + слой, который живёт у него дома. Инвентарь (research/personal-layer.md)
делит этот слой на три корзины.

| что | где живёт сейчас | вердикт | как |
|---|---|---|---|
| Status-хуки Claude/Codex/Gemini/Cursor/…, `agx-session-restore.sh`, `agx-session-context.sh`, `agx-agent-failure.sh` | `~/.config/agx/agent-status/` + блоки в `~/.claude/settings.json`, `~/.codex/config.toml` | **продукт даёт** (уже: Help ▸ Install Agent Status Hooks) | остаётся; в чеклисте — строка «Agent hooks» с живым статусом |
| Скилл `agterm` (control API для агента) | `~/.claude/skills/agterm/`, `~/.codex/…` | **продукт даёт** (уже: Help ▸ Install Agent Skill) | остаётся; строка чеклиста |
| `agtermctl` + `agx` в `/usr/local/bin` | симлинки из бандла | **продукт даёт** (уже) | строка чеклиста |
| Правило «закрой сессию» = `agtermctl session close --target $AGTERM_SESSION_ID`, не хендофф | только `~/CLAUDE.md` Руслана | **харнес** — переносим в `agx context` (MANIFEST) | сделано в этой ветке, см. §5. Текст попадает каждому агенту в каждой панели через SessionStart-хук (Claude) / brief-prefix (остальные) |
| Правило «`agx spawn`/`agtermctl` — штатный инструмент, не спрашивать» + `Bash(agx:*)`, `Bash(agtermctl:*)` в permissions.allow | `~/CLAUDE.md` + `~/.claude/settings.json` | **харнес, opt-in** — отдельный пункт | Не пишем permissions молча. В Welcome-панели у строки «Agent hooks» — подсказка «Claude Code may ask before every `agx` call; allow `Bash(agx:*)` in its permissions» + кнопка Copy (в MVP не собрано — см. §4). Инсталлер хуков permissions НЕ трогает (это чужая политика безопасности). Решил сам: писать allow-правила из приложения — превышение полномочий |
| «Коммит и деплой без подтверждения», ветки/worktree | `~/CLAUDE.md` | **личное** (правило мейнтейнера для этого репо) | не трогаем |
| `keymap.conf`: `command "Студия" cmd+shift+s …/mmee/…`, «Скиллы — отчёт» | `~/.config/agx/keymap.conf` | **личное** | не трогаем; пример «свои команды в keymap» остаётся в гайде (`keyboard.md#custom-keymap`) |
| `ghostty.conf`: `shell-integration-features = cursor,sudo,title` (без `ssh-*`, т.к. agx не шипит бинарь `ghostty`) | `~/.config/agx/ghostty.conf` | **дефолт продукта** — баг упаковки, ловит каждый | вне скоупа онбординга; записал в §4 как отдельный TODO (`ghostty-defaults.conf` в бандле) |
| amem (`team/agx/*`, `team/agterm/*`) | `~/amem` | **личное / контрибьюторское** | нет |
| `CLAUDE_CODE_SUBAGENT_MODEL`, rtk, screenshot-guard и прочие хуки | `~/.claude/settings.json` | **личное**, к agx не относится | нет |
| launchd-агенты для agx | — | нет ни одного (agx — foreground-приложение; schedule заменил launchd) | — |
| `~/Library/Application Support/agx/settings.json`: один connected agent (Claude Code) | state dir | **настройка** (Settings ▸ Agents) | строка чеклиста «Connect an agent» читает `settings.agents` |

Правило-вывод: продукт даёт то, что нужно **любому** агенту в **любой** панели (хуки, скилл, CLI,
текст `agx context`). Личное — то, что содержит пути Руслана, его репо или его политику доверия.
Настройкой становится то, что у разных людей разное, но обязано где-то быть (какой агент, в какой папке).

### «Закрой сессию» — в харнес

Было: абзац в `~/CLAUDE.md`. Стало: строка в `MANIFEST` у `scripts/agx` (`agx context`), рядом с
«set my own status glyph»:

```
  close MY OWN session (the user says "close this session/tab", not "hand off"):
      finish the handoff/log first, then  agtermctl session close --target "$AGTERM_SESSION_ID"
      (yours, never `active`); outside agx (AGTERM_ENABLED unset) just end the turn.
```

Почему в `agx context`, а не в скилле: скилл — справочник по API, его читают по триггеру; `agx context` —
то, что агент получает **всегда** при старте панели (Claude — хуком, другие — префиксом брифа). Правило про
смысл фразы должно быть там, где агент точно его увидит.

## 2. Интеграция с чужим окружением

Аудит трёх инсталлеров на `26c9fd4` — research/installers-audit.md. Коротко:

| инсталлер | куда пишет | честность | дыры |
|---|---|---|---|
| Agent Status Hooks (`AgentHooksInstaller`, generic по `agents/*/agent.json`) | `~/.config/agx/agent-status/` (wipe+copy), `~/.claude/settings.json`, `~/.gemini/settings.json` (jsonHooks), `~/.codex/config.toml` (tomlHooks, блок `# >>> agterm agent-status >>> … # <<<`), `~/.config/opencode/plugins/agterm-status.js`, `~/.pi/agent/extensions/agterm-status.ts` (plugin), `~/.zshrc`/`~/.bashrc`/fish | append-only, чужие хуки не трогает; идемпотентен (jsonHooks — по пути скрипта, toml — по маркерам, plugin — по маркеру владения в файле); `.bak` для json/toml; гейт «config-dir агента существует» — Claude больше не особый | **нет Uninstall** ни для одного вида; plugin без бэкапа; jsonHooks без текстового маркера владения (в JSON его негде хранить — путь `/agent-status/` и есть маркер); абсолютные пути из бандла тухнут после `make deploy` до повторного запуска инсталлера; Cursor-диалект есть в коде, нет в манифесте |
| Agent Skill (`SkillInstaller`) | `~/.claude/skills/agterm/`, `~/.codex/skills/agterm/` (copy) | не трогает чужую папку без маркера `<!-- agterm-skill -->` в SKILL.md; dangling symlink не считает «пусто» | нет Uninstall; копия, не симлинк → тихо отстаёт от бандла |
| Command Line Tool (`CLIInstaller`) | `/usr/local/bin/{agtermctl,agx}` (symlink, один admin-prompt) | — | **нет проверки владельца**: `ln -sf` поверх чего угодно с таким именем; нет Uninstall |
| Первый запуск | `WelcomeAlert` c двумя галочками ON по умолчанию → «Install» ставит skill+hooks | всё явно перечислено в алерте; `welcomeShown` ставится до инсталляции | дефолт «оба ON + Install — кнопка по умолчанию» = один Enter пишет в `~/.claude/settings.json`. Не «молча», но близко |
| Статус «установлено?» | — | — | **нет ни одного query API**; меню не показывает состояние; в control API/tree ничего |

Принципы (контракт онбординга):
1. **Ничего не пишется вне state-dir без нажатия на конкретную строку.** Первый запуск больше не
   предлагает «Install» одной кнопкой — Welcome-панель показывает строки с состоянием, каждая ставится
   своей кнопкой. Старый alert с pre-checked галочками убран.
2. **Состояние читается из системы, не из флага «показывали».** Каждая строка чеклиста — probe:
   TCC/UN API, `lstat` симлинков, разбор `settings.json`/`config.toml`/plugin-файла по тем же
   правилам, по которым инсталлер решает «уже стоит».
3. **Видно, что и куда.** У строки — одно предложение «что напишет» (файлы), без генерённых блоков.
4. **Обратимость.** Пока — `.bak` рядом (json/toml) и текстовые маркеры. Uninstall — следующий шаг,
   не MVP; для CLI добавить проверку владельца (`readlink` указывает в `*/agx.app/Contents/*` → наш).
5. **Чужие агенты.** Codex/Gemini/OpenCode/Pi — через тот же манифест; их конфиги трогаются только если
   `~/.codex`/`~/.gemini`/… существует. Cursor/Mimo — только launch+resume, конфиг не трогаем.
6. **Permissions Claude Code (`Bash(agx:*)`) не пишем** — показываем подсказку с Copy (отложено, §4).

Дыры, не закрытые в этой ветке (backlog): Uninstall для трёх инсталлеров; ownership-check в
CLIInstaller; авто-перебейк путей после `make deploy` (или относительный резолв через
`/usr/local/bin/agx`); Cursor status-манифест.

## 3. Онбординг как продукт

### 3a. Welcome-панель (первый запуск + Help ▸ Getting Started…)

Хост: `NSWindow(contentViewController: NSHostingController(rootView:))` — тот же приём, что
`AgentHooksResultView`, но **не модально** (`makeKeyAndOrderFront`, синглтон). Не NSAlert (чеклист с
кнопками в accessory view не живёт), не вкладка Settings (это не настройка). Решил сам.

Одна панель, три блока, сверху вниз:

**Set up** — строки с живым статусом (иконка · заголовок · одно предложение · метка · кнопка):

| строка | probe | кнопка |
|---|---|---|
| Notifications | `UNUserNotificationCenter.notificationSettings().authorizationStatus` | Allow… (request) / Open System Settings (denied) |
| Permissions for tools (Accessibility, Screen Recording, Full Disk Access) | `AXIsProcessTrusted()`, `CGPreflightScreenCaptureAccess()`, чтение `~/Library/Safari` (FDA без диалога) | Review… → `PermissionsAlert` (стена папок). Строка **optional**: не блокирует «всё готово» |
| Command line tool | `/usr/local/bin/{agtermctl,agx}` — симлинк, цель существует и лежит в `agx.app` | Install… → `CLIInstaller.run()` |
| Agent status hooks | `~/.config/agx/agent-status/` + per-agent: jsonHooks — путь скрипта в `settings.json`; tomlHooks — маркер-блок; plugin — файл с маркером. Показывает «Claude Code, Codex» | Install… → `AgentHooksInstaller.run()` |
| Agent skill | `SKILL.md` с маркером в `~/.claude/skills/agterm` или `~/.codex/skills/agterm` | Install… → `SkillInstaller.run()` |
| Connect an agent | `settings.agents` не пуст; детали — «N found on this Mac» | Open Settings… → Settings ▸ Agents |

Обновление: при показе панели и раз в 2 с, пока открыта (TCC меняется в System Settings, инсталлеры
пишут файлы). Когда все non-optional строки done — заголовок блока говорит «Setup complete».

**First moves** — 6 шагов, показывающих силу; каждый с ✓ если «открыт» (3c) и подсказкой «как»:
1. Spawn an agent with a brief (`agx spawn --brief "…"` из панели агента)
2. See the status glyph (сайдбар: ● working · ✓ done · ⛔ waiting) — открывается первым `session.status` от хука
3. Hold ⌥ — имена и шорткаты всех кнопок
4. Palette (⌃P) — любое действие без мыши
5. Reader — `agx reader plan.md`: документ рядом с шеллом
6. Dashboard (⌘⇧G) — все живые сессии одной сеткой

**Discovered N of M** — прогресс по полной карте (3c) + нераскрытое с подсказками.
Футер: «Open Guide» (docs/guide/README.md в репо; когда гайд попадёт в бандл/сайт — сменить URL),
«Close». На главы гайда ссылаемся по файлу и якорю (`agents.md#spawning-with-a-brief`,
`keyboard.md#-names-the-chrome`, `reader.md`, `model.md#quick-terminal-and-dashboard`), текст не дублируем.
Кнопку на Keyboard Shortcuts не ставлю: параллельная сессия ещё не зафиксировала имя действия — подключить
после её мержа одной строкой.

Когда показывать: авто — только на первом запуске (`FirstRunWelcome.isDue`; апгрейдеры, как Руслан,
не видят — заходят через Help). Help ▸ Getting Started… — всегда. «Не показывать повторно тем, у кого
всё done» выполняется автоматически: авто-показ одноразовый. Решил сам: не делать авто-показ «пока не
всё done» на каждом запуске — это nag.

Первый запуск теперь: панель Welcome вместо `WelcomeAlert`; стена разрешений автоматически **не**
открывается (её роль — строка «Permissions for tools» с кнопкой Review…), `permissionsPrimerShown`
ставится вместе с `welcomeShown`. Для апгрейдера (welcome не due, primer due) поведение прежнее.

### 3b. Первые действия — почему именно эти
spawn — главная фича (агент рождается с задачей); статус-глиф — то, ради чего хуки; ⌥ — самый дешёвый
способ выучить интерфейс; палитра — клавиатурный доступ ко всему; ридер — агент показывает документ, не
пастит в чат; дашборд — «много агентов разом». Split/scratch/schedule/failover/overlay/quick — в полной
карте, но не в первых шагах: split и scratch человек и так найдёт, schedule/failover — про второй день.

### 3c. Измерение понимания — карта открытых возможностей

Локально, без телеметрии: `<stateDir>/discoveries.json` — `{ "<id>": "<ISO first time>" }`.
Источник событий — **журнал действий**: `ActionJournal.log` — единственная воронка для чордов,
действий палитры/кеймапа, мутирующих control-запросов и state-флипов. `DiscoveryTracker` подписан
на журнал (`ActionJournal.observer`), `Discovery.match(kind:fields:)` переводит запись в id:

| id | признак в журнале |
|---|---|
| `spawn` | control `session.new` с `via=agx-spawn` (командная строка содержит `agx-brief-` — tempfile брифа) |
| `statusGlyph` | control `session.status` |
| `optionHints` | state `hints=on` (новая строка в `OptionHintsMonitor`) |
| `palette` | action `source=palette` |
| `reader` | control `session.reader.open` |
| `dashboard` | state `dashboard=on` (новая строка в `DashboardController.open`) |
| `split` | state `split=on` |
| `scratch` | state `scratch=on` |
| `overlay` | control `session.overlay.open` (в т.ч. `agx run`) |
| `schedule` | control `schedule.add` |
| `failover` | state `failover=handoff` (новая строка в `AgentFailoverCoordinator`) |
| `quickTerminal` | action `toggle_quick_terminal` |
| `workspaceDefaults` | control `workspace.defaults` |
| `hud` | control `session.hud` |

Честные границы: control-запрос журналируется при получении, до проверки цели — неудачный
`session.reader.open` тоже «откроет» reader. Для MVP приемлемо; точнее — журналировать после успешного
dispatch (следующий шаг). Считаем **первое** событие, не частоту: карта отвечает «человек это трогал»,
а не «понял». «Понял» = всё раскрыто И setup done; это единственная метрика панели.

Control API (правило проекта «каждая фича — через control»): в MVP команду не добавляю; backlog —
`agtermctl onboarding [--json]` (setup-строки + discoveries), `onboarding open|reset`, поле
`tree.onboarding`. Причина: команда тянет protocol/dispatcher/CLI/тесты/`site/commands.html`/скилл —
половина ночи, панель важнее. Решил сам.

## 4. Решения, принятые без Руслана

- **База ветки — `26c9fd4`, не `origin/master`.** Причина выше.
- **Welcome — немодальное `NSWindow` + `NSHostingController`, не `NSAlert` и не SwiftUI `Window`-сцена.**
  Решил сам, потому что: панель должна жить рядом с терминалом и обновляться, пока человек ставит
  галочки в System Settings (таймер 2 с); alert блокирует всё, а `Window`-сцена в `agtermApp.body`
  трогает файл, который правят две другие сессии. Тот же хост, что у `AgentHooksResultView`.
- **Окно ограничено высотой экрана и скроллится.** Решил сам: панель 905 pt, на 13" при крупном
  масштабе не влезает. `ScrollView` не имеет собственной fitting-высоты — контент меряется
  `NSHostingView.fittingSize`, окно получает `min(контент, экран − 60)`.
- **Строка «Permissions for the tools you run» — optional, не блокирует «Setup complete».** Решил сам:
  Accessibility/Screen Recording/FDA нужны не всем, а строка, держащая чеклист красным, толкает выдать
  больше, чем используется. Первый запуск больше НЕ открывает стену разрешений следом за Welcome —
  её кнопка «Review…» в панели и есть вход в стену (`permissionsPrimerShown` ставится вместе с
  `welcomeShown`). Для апгрейдеров (welcome уже показан, primer нет) старый путь оставлен.
- **Подсказка «allow `Bash(agx:*)`» с Copy — не собрана.** Решил сам: это отдельный текст про чужую
  политику безопасности, а MVP-панель и так на пределе высоты. Правило «permissions не пишем» стоит;
  подсказка — в бэклог (§2).
- **Спавн детектится по `agx-brief-` в `command` запроса `session.new`.** Решил сам: `agx spawn`
  кладёт бриф в `/tmp/agx-brief-*` (`agx run` — `agx-cmd-*`); отдельного поля «origin» в протоколе нет,
  а добавлять его ради карты — тянуть protocol/CLI/скилл. Записывается как `via=agx-spawn` в журнал.
- **Имена control-команд в карте — реальные raw-значения:** `session.reader.open`,
  `session.overlay.open`, `quick`. Проверено на Debug-инстансе: первый вариант (`session.reader`)
  ничего не ловил.
- **Ссылка «Open Guide» ведёт на GitHub (`Brand.homepage` + `/blob/master/docs/guide/…`).** Решил сам:
  гайд пишет параллельная сессия и в бандл он пока не попадает; локальный путь из worктри ломается
  при деплое.
- **Никакого «нажми, чтобы вернуться» nag'а и авто-показа при неполном чеклисте.** Показ — только
  первый запуск и Help ▸ Getting Started…; тем, у кого всё сделано, панель не навязывается.
- **Control-команды `onboarding.*` — нет** (см. §3c): половина ночи ради read-back, панель важнее.

## 5. Реализация (минимальная версия) — сделано

**agtermCore** (host-free, 10 тестов в `OnboardingTests`):
- `Onboarding.swift`: `Discovery` (12 capability, `firstMoves` — первые 6, `title`/`hint`/`guide`,
  `matches(kind:fields:)` — журнал → discoveries), `DiscoveryStore` (`<state>/discoveries.json`,
  ISO-8601 «когда впервые»), `DiscoveryTracker` (первый раз — запись, `reset`, `attach(to:)`),
  `OnboardingSetup` (шаги чеклиста, `State` done/pending/optional/unknown, `isComplete`,
  `linkPointsIntoBundle`, копирайт строк).
- `ActionJournal.setObserver` — один слушатель на очереди журнала; карта строится из тех же записей,
  что и файл.
- Новые сигналы в журнал: `state dashboard=on` (`DashboardController.open`), `state hints=on`
  (`OptionHints`, ⌥ вниз), `state failover=handoff` (`AgentFailoverCoordinator`), `control … via=agx-spawn`
  (`ControlServer.journal`).
- `FirstRunWelcome` — только `hasPriorState`/`isDue`; тексты alert'а удалены вместе с `WelcomeAlert`.

**app**:
- `Onboarding/OnboardingProbe.swift` — живые чеки: `UNUserNotificationCenter`, `AXIsProcessTrusted`,
  `CGPreflightScreenCaptureAccess`, FDA через `TCC.db`, симлинки `/usr/local/bin/{agtermctl,agx}`
  (цель обязана лежать внутри `Bundle.main`), `AgentHooksInstaller.status()` (новый read-only статус
  через тот же merge, что и инсталлер: «changed == false» ⇒ установлено), маркер скилла на диске,
  `settings.agents` + `AgentCatalog.detectInstalled()`.
- `Onboarding/WelcomeWindow.swift` — `WelcomeModel` (таймер 2 с, действия строк: `requestNotifications`,
  `PermissionsAlert.present`, `CLIInstaller.run`, `AgentHooksInstaller.run`, `SkillInstaller.run`,
  Settings ▸ Agents через `SettingsView.openAgentsTab`) и `WelcomeWindow` (один экземпляр, `present` /
  `presentOnFirstLaunch` / `close`).
- `Views/WelcomeView.swift` — заголовок, карточка «Set up» (`welcome-<step>`, `welcome-<step>-action`),
  «First moves» (`welcome-move-<id>`), «Discovered N of M» + «Still to try», футер Open Guide /
  Reset Discoveries / Close.
- `agtermApp.swift` — `DiscoveryTracker` создаётся в `init`, `attach` к журналу; первый запуск →
  `WelcomeWindow.presentOnFirstLaunch`. `agtermApp+Menus.swift` — один пункт Help ▸ Getting Started….
- `SettingsView.openAgentsTab` — уведомление, переключающее вкладку.
- UI-тест `WelcomeUITests` переписан под окно (`welcome-close`, строки, `welcome-move-spawn`).

**harness**: `scripts/agx` MANIFEST — строка «close MY OWN session …» с правилом «закрой сессию» =
эта вкладка, не хендофф.

**Проверено руками** на изолированном Debug-инстансе (`AGTERM_STATE_DIR=/tmp/agxob`): панель
открывается на первом запуске, строки читаются с системы (hooks/skill — done, CLI — «points at another
build», агент — «Found on this Mac: …»), `session split` / `reader open` / `status` / `quick` через
изолированный сокет зажигают 4 из 12 без перезапуска панели.

**Не проверено**: кнопки Install…/Allow…/Review… с Debug-инстанса не нажимались (запрет CLAUDE.md —
пишут в `~/.claude` и `~/.config/agx`); их проверит Руслан из задеплоенного Release. `agx spawn`
детект (`via=agx-spawn`) — только unit-тест матчера, живой спавн не гонялся.
