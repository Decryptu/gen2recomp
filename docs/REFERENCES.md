# External source references

This project uses the pret disassemblies as authoritative references when
matching original game behavior. They are comparison sources, not project
content. Do not copy ROMs, extracted cartridge data, or a complete external
checkout into the project history.

## Pinned repositories

The exact revisions used by the local workflow are recorded in
[`references.lock`](../references.lock).

| Game | Repository | Pinned revision | Useful areas |
| --- | --- | --- | --- |
| Crystal | [pret/pokecrystal](https://github.com/pret/pokecrystal) | `5593381195342e481b69a2fd4ab25e202ddcf708` | Maps, scripts, events, data, battle behavior |
| Gold and Silver | [pret/pokegold](https://github.com/pret/pokegold) | `add1dbe018170d7f25f7b7360e8046cec6354906` | Maps, scripts, events, data, battle behavior |

The lock file is the machine-readable source of truth. The revisions are
deliberately pinned so that source comparisons remain reproducible. The branch
name recorded there is the upstream branch used when each revision was pinned;
it is not used as a substitute for the commit hash.

## Local checkout workflow

Run these commands from the project root:

```sh
bash tools/fetch_reference_sources.sh
bash tools/reference_status.sh
bash tools/reference_status.sh --remote
```

The default checkout root is `.references/`. It is ignored by the project and
is safe to remove and recreate. Set `GEN2_REFERENCE_ROOT` or pass a first
argument to either script to use another local directory:

```sh
GEN2_REFERENCE_ROOT=/path/to/reference-cache bash tools/fetch_reference_sources.sh
bash tools/reference_status.sh /path/to/reference-cache
```

The fetch script clones a missing repository, fetches the locked revision, and
checks it out detached. Existing repositories must have the expected origin
and no local edits. The script refuses to replace local work or silently move
the checkout to another revision.

The status script reports whether each checkout is missing, dirty, at the wrong
revision, or ready for comparison. With `--remote`, it also reports when the
recorded upstream branch has moved beyond the pinned revision. Updating a pin
is a deliberate maintenance change: inspect the source changes, update
`references.lock`, and document the reason in the relevant project handoff.

## Source lookup guide

The two repositories use closely related paths. Check the matching path in
`pokegold` when behavior differs between Gold and Silver and Crystal.

| Behavior | Primary source paths |
| --- | --- |
| Map scripts and scenes | `maps/*.asm`, `data/maps/scenes.asm` |
| Script command widths and dispatch | `macros/scripts/events.asm`, `engine/overworld/scripting.asm` |
| Special event handlers | `data/events/special_pointers.asm`, `engine/events/specials.asm` |
| Party health and recovery | `engine/pokemon/health.asm`, `engine/events/whiteout.asm` |
| Save behavior | `ram/sram.asm`, `engine/menus/save.asm` |
| Map connections and warps | `data/maps/attributes.asm`, the matching map files and overworld warp code |
| Wild encounters | `data/wild/*.asm`, `data/wild/fish.asm` |
| Trainer parties and data | `data/trainers/parties.asm`, the matching trainer data files |

When a source fact changes runtime behavior, record the source file and symbol
near the implementation or in the project handoff. For facts tied to a
particular source revision, record the pinned commit as well. Source-derived
data should stay outside tracked files unless it is a small, verified runtime
table or test fixture required by the project.
