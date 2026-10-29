# poi-perplayer — POI для каждого игрока

Вилка world-мода `poi` (2.1.1): каждый игрок видит и правит **свои** точки;
неprefixed-ключи из `poi.perplayer_global` — **общие read-only** для всех.
Деплой на smorodinka: 06.09 (заменил `poi` в `worlds/smorodinka/worldmods/poi`).

## Модель данных
- Ключи в `mod_storage.sqlite`: `имя@ник` (личные), `имя` без суффикса (глобальные).
- View игрока = глобальные + его личные (как bare-имена) — строится на каждое
  действие (`PPL.view(name)`), маппинг bare→owned происходит в `poi.save()`.
- Миграция при старте: легаси-ключи без суффикса (кроме глобальных) уходят
  `poi.perplayer_default_owner`. Однократно, маркер в action-логе.

## Шаринг точек: /poi_global
- `/poi_global` — список общих (config-объявленные + расшаренные командой).
- `/poi_global <имя>` — расшарить СВОЮ точку (становится read-only для всех).
  Повтор команды тем же игроком (или admin с привилегией `server`) — снять шаринг,
  точка возвращается в личный список.
- Точки из `poi.perplayer_global` снимаются только правкой конфига.
- Коллизии: своя тень общей точки не мешает; promote занятого имени отклоняется.
- Расшаренные через команду переживают рестарт (storage-ключ `_pp_globals`).

## Настройки (main-config/minetest.conf)

> Сервер читает только `main-config/minetest.conf`; world-level conf не применяется
> (проверено 06.09: world-conf молча игнорируется).
```
poi.perplayer_global = init_spawn          # общие точки, read-only для всех
poi.perplayer_default_owner = spluft       # владелец легаси-точек при миграции
```

## Что патчится поверх оригинала (блок в конце init.lua)
- `openlist/save` — снапшот storage + read-modify-write flush только своего среза
  (оригинальный `save()` затирает всю таблицу — главный камень);
- `set/delete/jump/move/rename/gui/list/exist` — обёртки с `PPL.view()`;
- глобальные protected от delete/move/rename;
- маркер загрузки: `[MOD] poi_perplayer layer loaded: N shared global POI(s)`.

## История: баг формата ключей (тот же день)
Первая ревизия слоя писала ключи как `владелец@точка` вместо `точка@владелец` —
поймано тестом tests/test_layers.lua (13 кейсов, мок minetest, lua5.1). Легаси-данные
не пострадали; фикс + тоггл-демуплекс задеплоены 06.09 12:51.

## Верификация (06.09)
- stdout: маркер слоя + `[POI] perplayer migration done, owner=spluft`, 0 ERROR;
- mod_storage: `init_spawn` | `pillagers@spluft` | `village@spluft`;
- бэкапы: orig-мод в `worldmods/../poi-backup-orig-20260906` (вне пути сканирования),
  storage — `/opt/data/backups/mod_storage.sqlite.pre-poi-perplayer-20260906`.

## Известные ограничения
- Имена POI уникальны в рамках игрока; у двух игроков могут быть одноимённые точки.
- `/poi_validate` не обёрнут (валидирует view последнего игрока) — косметика.
- Привилегия `poi` по-прежнему нужна для set/delete/move/rename (`privs={poi=true}`
  у команд не меняли) — у matway её нет, он пока только читает и прыгает.

## Тест-план (не выполнен — принято осознанно, low-risk)
- in-game: matway ставит точку → spluft её не видит; spluft удаляет свою → matway
  не теряет; глобальная `init_spawn` видна обоим, delete отклоняется.

## Upstream
- Repo: https://github.com/acmgit/minetest_poi — this repo carries the full upstream history; our commits sit directly on top of upstream master d444ad5 (2025-10-12, last upstream commit). The earlier pristine-snapshot commit 658d809 was verified byte-identical to d444ad5 and was rebased away on 2026-10-29 so this is a proper fork with shared history.
- Upstream status: alive but dormant — last commit 2025-10-12 (null->nil lint fix). No per-player feature; our fork is NOT superseded.
- Update check: git remote add upstream https://github.com/acmgit/minetest_poi; git fetch upstream; git diff d444ad5..upstream/master -- init.lua
