## What this changes

<!-- One or two sentences. What behaves differently after this merges. -->

## Source references

<!--
Behavior is re-derived from the pokecrystal / pokegold disassemblies. For
anything that reproduces cartridge behavior, cite path plus symbol, one per line:

  engine/battle/core.asm, DetermineMoveOrder

Write "not source-derived" for tooling, docs, launcher or export work.
-->

## How it was verified

- [ ] `--headless --editor --quit` scan passes (required after adding scripts)
- [ ] GUT suite passes
- [ ] Screenshot attached (required for visual changes)
- [ ] Boot smoke test passes

<!-- Paste the GUT summary line, and drag any screenshots in here. -->

## Checklist

- [ ] No ROM-derived, generated, cache or local-only file is staged
- [ ] `git diff --cached --check` is clean
- [ ] `HANDOFF.md` updated if deliberate behavior, scaffolding or known breaks changed
- [ ] Defects met along the way are fixed here or recorded in `HANDOFF.md` open work
- [ ] Docs updated if a contract in `docs/` changed
