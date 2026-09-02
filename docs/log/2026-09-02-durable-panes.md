# 2026-09-02 — Durable agent panes (abduco soft restart)

Состояние: реализовано, задеплоено, закоммичено (2 коммита). Не запушено. Ждёт живой
проверки Русланом после перезапуска app.

## Что сделано
- ADR `docs/decisions/0001-abduco-durable-panes.md` (accepted, дефолт ON).
- Ядро `agtermCore/DurablePane.swift` + тесты; протокол/диспетчер/CLI `--durable`, read-back
  `durable` на ноде; `AppSettings.durablePanes` (nil=ON); `AppStore.sessionDiscardSink` (только
  реальное закрытие, не quit/close-window).
- App `agterm/DurableSpawn.swift`: обёртка спавна (`abduco -A -f <state>/abduco/<uuid> zsh -lc
  'printf $$ >…pid; exec <line>'`), чтение pid-файла для правдивого `tree.foreground`, SIGTERM
  серверу на discard. Деградация к обычному спавну при отсутствии бинаря / длинном state dir.
- `vendor/abduco/abduco.c`: патч `session_wait_gone()` против гонки сокета в `-A -f` (0.6 баг).
  Документирован в `vendor/abduco/PATCHES.md`.
- `setup.sh` собирает abduco (`-D_DARWIN_C_SOURCE`), `project.yml` бандлит в `Resources/abduco`.

## Коммиты
- `b9f9634` — agx groundwork (context/spawn/usage/preflight/ssh) из прошлых сессий, вынесен
  отдельно, т.к. durable стоит поверх него (общие файлы разложены по хункам).
- `8879252` — durable agent panes.

## Гейты
- `swift test` 2608 ✓; DurablePane/dispatcher/CLI/tree/discard ✓; `make lint` ✓; Debug build ✓.
- `make test-app`: 7 падений — предсуществующая flakiness (те же 7 на чистом HEAD).
- Живая изоляция: durable claude пережил quit+relaunch с тем же PID; close убил сервер.
- Standalone `scripts/durable-proto.py`: 13 проверок ✓.

## Открыто
- НЕ запушено (по правилам — отдельно).
- Первый перезапуск на новом бинаре форкнёт текущие сессии один раз (миграция), дальше мягко.
- Тестовая сессия для проверки: `22DEBA7E` в воркспейсе `durable-test`, якорь
  `DURABLE-ANCHOR-7F9D`, контекст ~80k. Шаги проверки — в конце диалога.

## Вечер: первый рестарт и добор (сессия durable-test)

- Первый рестарт на новом бинаре прошёл как миграция: все 5 abduco-серверов стартовали в 20:15:55,
  через секунду после app (20:15:54) — форк `--resume --fork-session`, не реаттач. Ожидаемо (ADR §7):
  до рестарта работал старый бинарь без abduco. **Проверка кодовым словом ничего не доказывает** —
  `--resume` тоже возвращает контекст. Настоящий тест — следующий рестарт.
- Добавлено, чтобы следующий рестарт сам дал улику: `Session.durableAttached` → `tree.attached`
  (true = реаттач, false = fallback); событие `session.durable {attached}`; тег `reattached` в
  `agx context`; reaper `DurableSpawn.reapOrphans` на старте (известные id — `WindowLibrary.
  persistedSessionIDs()`, все индексированные окна, загруженные и нет). Тесты: orphans, formatter,
  tree.attached, event, persistedSessionIDs.
- Как проверить после рестарта: `agtermctl tree --json | grep -o '"attached":[a-z]*'` — все `true`;
  либо `ps -Ao pid,lstart,command | grep '[a]bduco -A'` — время старта серверов старше времени app.
- Сеть: в 15:26–15:47 UTC пять сессий молча висели 5–12 мин и умерли с `API Error: Connection lost
  mid-response` / `ECONNRESET`; Claude Code не ретраит и не возобновляет сам, юзер набирал «продолжи».
  Разбор — `scratchpad/api-error-analysis.md` этой сессии; задача оформлена в `docs/backlog/`.
- Изолированная проверка Debug-инстанса (`AGTERM_STATE_DIR=/tmp/agx-d2`, `sleep 3000` как программа):
  create → `durable:true, attached:false`; SIGTERM app → сервер и программа живы (ppid 1); relaunch →
  `attached:true`, тот же pid программы; подложенный сирота-сокет убран reaper'ом; `session close` →
  сервер умер; `events --kind session.durable` отдаёт событие. Gotcha: сокет изолированного инстанса
  появляется только после рендера окна — после `open -n` нужен `open -b uz.marshub.agx.debug`.
- `ControlProtocol.swift` перелил лимит 1000 строк → узлы дерева вынесены в `ControlTreeNodes.swift`
  (механический перенос). Гейты: `swift test` 2611 ✓, `make lint` ✓, Debug и Release build ✓.
