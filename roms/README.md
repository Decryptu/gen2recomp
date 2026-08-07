# Your cartridges go here

The project ships no game data. Put your own dumps here, for example
`roms/gold.gbc`, `roms/silver.gbc`, `roms/crystal.gbc`.

Everything here except this file is gitignored and excluded from Godot imports
by `.gdignore`, so it cannot enter commits or exports. Keep `.gdignore`.

```bash
godot --headless --path . -s res://tools/verify_rom.gd -- roms
```

Names do not matter: every file is matched by SHA-1 against the supported
cartridges listed in [the README](../README.md#supported-cartridges). Unknown
hashes are refused rather than imported with an uncharacterised bank layout that
could produce corrupt assets.
