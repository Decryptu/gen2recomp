# Your cartridges go here

gen2recomp ships no game data. Drop your own dumps in this folder and the
tooling will find them:

```
roms/gold.gbc
roms/silver.gbc
roms/crystal.gbc
```

Everything in here is gitignored except this file. Nothing you put in this
folder will ever be committed or end up in a build.

## Why it is safe to keep them inside the project

Two independent mechanisms:

- **`.gitignore` + the pre-commit hook** keep them out of the repository. The
  hook checks staged blobs by extension *and* by size, so even a renamed dump
  with no extension is refused.
- **`.gdignore`** makes Godot's resource system skip this directory entirely,
  so the files are never imported and never swept into an export. That file must
  stay here; deleting it would let a build pick up a cartridge.

## Checking your files

```bash
godot --headless --path . -s res://tools/verify_rom.gd -- roms
```

Every file is matched by SHA-1, never by filename, so the name you choose is
only for your own convenience. Supported dumps:

| Game | SHA-1 |
|---|---|
| Gold (USA/Europe) | `d8b8a3600a465308c9953dfa04f0081c05bdcb94` |
| Silver (USA/Europe) | `49b163f7e57702bc939d642a18f591de55d92dae` |
| Crystal (USA/Europe Rev 1) | `f2f52230b536214ef7c9924f483392993e226cfb` |

An unrecognised hash is refused outright rather than imported on a best-effort
basis: a cartridge whose bank layout has not been characterised would produce
corrupt assets instead of an honest error.
