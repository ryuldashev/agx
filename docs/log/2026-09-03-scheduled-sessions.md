# 2026-09-03 — Scheduled sessions (native `schedule.*`)

Состояние: реализовано, гейты пройдены (см. ниже), задеплоено. Не закоммичено, не запушено.

## Что сделано
- Ядро `agtermCore/ScheduledSession.swift`: модель `ScheduledSession`, `ScheduleStore`
  (`<stateDir>/scheduled.json` + `scheduled/<id>.brief`), `SchedulePolicy` (grace 24h → `missed`),
  `ScheduleTime.parse` (+Ns/m/h/d, HH:MM, tomorrow [HH:MM], YYYY-MM-DD [HH:MM], ISO 8601),
  `ScheduledLaunch.commandLine` (тот же приём, что `agx spawn`: brief через файл → `exec agent "$b"`).
- Протокол `schedule.add/list/cancel/run`, `ControlArgs.at/brief`, `ControlResult.scheduled`,
  `ControlTree.scheduled`, события `schedule.added/fired/cancelled/missed` (+ `payload.at`).
- Диспетчер `ControlDispatcher+Schedule.swift` (валидация host-free), CLI `agtermctl schedule …`
  (`--brief|--brief-file`, `--workspace` по умолчанию из `AGTERM_WORKSPACE_ID`).
- App: `SessionScheduler` (таймер на main runloop, sweep на старте после `reopenWindows` и на
  `screensDidWake`, уведомление при fire/missed), `ControlServer+Schedule.swift` (резолв воркспейса
  и агента), стоп в `applicationWillTerminate`.
- `scripts/agx`: `agx schedule …` passthrough + строка в MANIFEST контекст-хука.
- Доки: skill reference/SKILL, control-api.md, site/commands.html, FORK.md.

## Гейты
- `swift test` ✓ (2638+), `make lint` ✓ (ControlDispatcher.swift ровно 1000 строк — следующий
  протокольный метод потребует выноса), Debug build ✓.
- Живая проверка в изолированном инстансе (`AGTERM_STATE_DIR=/tmp/agxsched`): `schedule add --at +15s
  --command "zsh -c 'echo brief was:; echo \"$1\"'"` → через 15 с появилась сессия, текст brief
  дословно в пане, `scheduled.json` опустел, brief-файл удалён.
- `make test-app`: 7 падений (FullScreenChord/SidebarExpansionMirror/SystemWakeObserver/UndoCloseShortcut),
  все от одного `malloc: pointer being freed was not allocated` в тест-хосте; тот же набор и тот же крэш
  на чистом master `31bcfd4` — предсуществующее, не flaky, стоит разобрать отдельно.

## Открыто
- Живые сессии, открытые ДО рестарта, узнают о команде только из нового текста контекст-хука
  (`agx context`) или подсказки в промпте — их системный промпт уже собран.
- Fire при отсутствии открытого окна — job остаётся `overdue` до следующего sweep (wake/launch).
