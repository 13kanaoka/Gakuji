# lib/unused/

Parked screens that are **not wired into the app** — nothing imports them and
no route reaches them. They were standalone dev/test harnesses for the
detective game's animation and flow work.

They are kept here (rather than deleted) for reference. `lib/unused/**` is
excluded from the analyzer in `analysis_options.yaml`, so these files are not
lint-checked and their imports are not kept up to date with the rest of the
codebase.

If you revive one, move it back under `lib/features/games/` and fix its imports.
If it's clearly obsolete, delete it.
