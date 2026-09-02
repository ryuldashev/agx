# 2026-09-02 — agx: смарт-контекст, spawn+seed, сквозной usage, abduco

Фича «интерфейс знает себя»: агент внутри AGX понимает, где он, что видит юзер, что умеет, и
может рулить UI сам. Всё собрано и отдогфужено в этой сессии.

## Что появилось
- **`~/agterm/scripts/agx`** (симлинк `~/.local/bin/agx`) — CLI поверх agtermctl:
  - `context` — «me / что видит юзер / открытые сессии / манифест умений + честные лимиты».
  - `spawn --brief --name [--workspace-name] [--cwd] [--foreground]` — создаёт сессию и запускает
    claude с брифом как ПЕРВЫМ сообщением (без TUI-typing race). Лечит empty-session bug.
  - `run "<cmd>"` — конечная команда в overlay своей же панели, печатает вывод + exit.
  - `usage` — джойнит эмиты статуслайна с живым деревом, кросс-сессионный расход.
- **SessionStart-хук** `~/.claude/hooks/agx-session-context.sh` — гейт на `AGTERM_ENABLED=1`,
  инжектит `agx context` в additionalContext. Зарегистрирован в `~/.claude/settings.json`.
- **Статуслайн** `~/.claude/bin/statusline.sh` — 5h/7d пулы, абсолютный контекст (Nk) + ⚠2x ≥200k,
  и пишет метрики в `~/.claude/agx-usage/<AGTERM_SESSION_ID>.json` (atomic).
- **Нативная панель** `agterm/Views/UsagePanel.swift` в футере сайдбара
  (`WindowContentView.swift` → `sidebarFooter`): читает те же эмиты, показывает 5h/7d/$total/count/⚠,
  попап с раскладкой по сессиям. Скомпилирована в деплой.
- **abduco** (durable panes) — доделана в соседней сессии (029A98D7), вживлена в Swift.

## Два готча spawn (закрыты сегодня)
1. Дефолтный воркспейс был фокусный (default у `session new`), не воркспейс вызывающего →
   теперь без `--workspace` дефолт = `$AGTERM_WORKSPACE_ID`. Проверено: спавн из mmee сел в mmee.
2. Спавн в недоверенную Claude'у папку упирался в разовый trust-диалог до старта брифа. Гейт НЕ
   обходим (защитная фича) — `spawn` читает `~/.claude.json → projects[<abs>].hasTrustDialogAccepted`
   и печатает предупреждение (+ `cwd_trusted` в --json), если доверия нет.

## Ключевые уроки (для следующей сессии)
- `agtermctl tree --json` кладёт стейт под `result.tree.workspaces` (двойная вложенность).
- Позиционные, не флаги: `session move <workspace>`, `workspace new "<NAME>"`, `notify "<body>"`.
- Бриф надёжно садится только как argv `claude "$(cat brieffile)"`, не типингом в свежий TUI.
- Полный разбор умений/лимитов — `docs/backlog/agx-context-self-awareness.md`.
