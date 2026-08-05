# Your cartridges go here

The project ships no game data. Put your own dumps here, for example:

```
roms/gold.gbc
roms/silver.gbc
roms/crystal.gbc
```

Everything here except this file is gitignored and excluded from Godot imports
by `.gdignore`, so it cannot enter commits or exports. Keep `.gdignore`.

## Verify

```bash
godot --headless --path . -s res://tools/verify_rom.gd -- roms
```

Names do not matter; every file is matched by SHA-1.

| Game | SHA-1 |
|---|---|
| Gold (USA/Europe) | `d8b8a3600a465308c9953dfa04f0081c05bdcb94` |
| Silver (USA/Europe) | `49b163f7e57702bc939d642a18f591de55d92dae` |
| Crystal (USA/Europe Rev 1) | `f2f52230b536214ef7c9924f483392993e226cfb` |

Unknown hashes are refused rather than imported with an uncharacterised bank
layout that could produce corrupt assets.
