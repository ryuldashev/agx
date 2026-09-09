# 2026-09-07 — журнал действий (ActionJournal)

Состояние: код готов, ядро зелёное (2705 тестов), Debug-сборка проверена сквозным прогоном на
изолированном инстансе. Release собирается / деплой — по решению Руслана. **Не закоммичено**
(ветка `action-journal-2026-09-07` от `origin/master` 6c2efb2).

## Проблема
В сессии «Итоги ретаргета» поверх живой панели Claude включился scratch-терминал; выглядело как
«Клод выпал». Причину пришлось *реконструировать* (⌘J = «о» на русской раскладке — гипотеза), потому
что у agx не было никакого следа: ни нажатий, ни того, кто дёрнул действие (клавиша / палитра /
меню / сокет). Руслан: «нужно как минимум добавить телеметрию — что куда нажималось».

## Решение
`agtermCore/ActionJournal.swift` — append-only JSONL `<state dir>/journal.jsonl` (ротация в
`journal.1.jsonl` на 8 МБ), fire-and-forget на serial queue, никогда не бросает. Четыре слоя записей:

| kind | где пишется | что внутри |
|------|-------------|------------|
| `key` | `CustomCommandRunner` key monitor | только чорды с ⌘/⌃: `chord`, `produced` (символ раскладки), `keyCode`, `asciiLayout`, `focus`, `consumed`, `session`, `scratch` |
| `action` | `AppActions.perform` (keymap) / `runPaletteCommand` (palette) | `source`, `action` |
| `control` | `ControlServer.dispatch` | `cmd`, `target`, `mode`, `name`; читалки (`tree`, `events.read`, `window.list`, `session.text`) пропускаются |
| `state` | `AppStore.toggleScratch`, `setSplitVisibility`, `closeSession` | `scratch on/off`, `split on/off`, `closed` |

Меню и тулбар не журналируются отдельно: их чорд виден в `key` (`consumed:0` = ушёл в menu key
equivalent), а эффект — в `state`. Обычный набор текста не пишется никогда.

## Проверка
Изолированный Debug (`AGTERM_STATE_DIR=/tmp/agxj` + `AGTERM_UITEST_FORCE_SIDEBAR_VISIBLE=1`, иначе
first-run модалки блокируют `controlServer.start()`), через его сокет `scratch on/off`, `split`,
`rename`. Журнал показал ожидаемую цепочку `control → state`. Бонус: пока окно было впереди, Руслан
дважды нажал ⌘W — журнал записал `chord:cmd+w, produced:"ц", asciiLayout:0, consumed:0`, и следом
`state scratch off`. Ровно тот класс событий, ради которого всё делалось.

## Не сделано / дальше
- Перебиндинг `toggle_scratch` с `cmd+j` НЕ делается: дефолт апстрима (VS Code-style ⌘J), а причина
  инцидента ещё не доказана. Решать после первого пойманного повтора по журналу.
- `agtermctl journal -n N` как читалка — не нужен, пока хватает `tail`.
- Коммит и `make deploy` + перезапуск agx — Руслан.
