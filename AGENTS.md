# poi-perplayer

Luanti (Minetest) server-mod: per-player private Points-of-Interest layered on top of
stock `poi` 2.1.1. Each player sees and edits only their own POIs; named POIs promoted
to global are shared read-only. Deployed on the `smorodinka` world (Mineclonia game).

## Canonical tree — read first

The canonical tree is `repo/` itself — a nested git repo (`master`), gitignored by the
outer `luanti` docs repo. History is CTF-style, not branch-based: commit `658d809` +
tag `v2.1.1` is a pristine upstream snapshot of stock poi 2.1.1, and all fork changes
are purely additive commits on top, so `git diff v2.1.1..HEAD` is the entire patch.
Run git from inside `repo/` (`git -C repo log`); the parent repo never sees it. The
outer `projects/poi-perplayer/README.md` is a pointer page only; the old `mod/`
snapshot dir is deleted and journal references to it are stale.

## Architecture

- The entire perplayer feature is ONE wrapper layer block appended at the end of
  `init.lua`. Stock poi code above it is never edited. The layer defines `PPL` and
  shadows `poi.*` functions (`openlist/save/set/delete/jump/move/rename/gui/list/exist`)
  with wrappers; `PPL.view(name)` rebuilds each player's view (globals + own POIs as
  bare names) per action.
- Storage keys in `mod_storage.sqlite`: `point@player` = personal POI; bare `point` =
  global. Command-promoted globals persist under `_pp_globals`.
- Commands: `poi_set/delete/move/rename` and `/poi_gui` keep stock `privs={poi}`; the
  fork adds `/poi_global`, admin-only (`privs={server}`). `/poi_validate` is not
  wrapped — known cosmetic limitation.
- Mod name stays `poi` in `mod.conf` and folder name; renaming breaks the
  `mod_storage.sqlite` association.

## Dev & test loop

1. Edit `init.lua` (layer block only).
2. Run `lua5.1 tests/test_layers.lua` from `repo/` — it must print `ALL 13 TESTS PASS`
   (key format, privilege contract). Requires Lua 5.1; if absent, install it. Never
   claim a pass without running it. `tests/regen_tests.py` rebuilds the test file by
   slicing the layer block; fix its stale path or re-slice manually after layer edits.
3. Commit to the nested repo (`repo/`), imperative messages, one feature/fix per commit.
4. Deploy: PUT mod files into `worlds/smorodinka/worldmods/poi/` via the Portainer
   archive API, then restart the `luanti` container only when nobody is online.
5. Verify by load marker, not absence of errors: `[MOD] poi_perplayer layer loaded: ...`
   in container stdout (`docker logs luanti | grep MOD`), not in debug.txt.

## Do-not-touch

- Upstream snapshot commit `658d809` and tag `v2.1.1` must stay pristine. Never rebase,
  amend, or rewrite history below the fork point — additive commits only.
- Stock section of `init.lua` above the layer block. Extend only via wrappers so the
  diff stays a reviewable patch and upstream updates stay a mechanical reapply.
- `worlds/smorodinka/mod_storage.sqlite` — live POI data; back up before every deploy.
- `docs/log_history/` journal in the outer repo — append-only; add entries, never
  rewrite old ones.
- Backups of the stock mod live OUTSIDE any scan path; never park a mod dir inside
  `worldmods/` or `mods/` — it will be loaded.

## Gotchas

- Stock `poi.save()` overwrites the ENTIRE storage table. Every save path must go
  through the wrapped read-modify-write (snapshot + flush of only that player's
  slice) or it wipes other players' POIs. This is the original landmine.
- Key format is strictly `point@owner` (point first, owner second), NOT `owner@point`.
  The first fork revision inverted this and silently lost new POIs on relog; the key-
  format test exists to catch regressions — keep it.
- World-level `minetest.conf` is silently ignored by the engine — no error, no effect.
  Settings (`poi.perplayer_global`, `poi.perplayer_default_owner`) are read ONLY from
  `main-config/minetest.conf`; restart required.
- World mods belong only in `worlds/<world>/worldmods/`; `worlds/<world>/mods/` is
  ignored by the engine.
- POI names are unique per player; a personal POI deterministically shadows a same-
  named global (both survive save); promoting an already-taken name is rejected.