# Toolchain and reproducibility

- Runtime: official LÖVE 11.5 Windows x64 portable distribution.
- Archive: love-11.5-win64.zip.
- Source: https://github.com/love2d/love/releases/download/11.5/love-11.5-win64.zip
- Observed SHA-256: BA6E56BE2685E53C817749C4A5007F51137136FE5A3AB64920508BABC2E74369
- Pinned values live in toolchain.json; setup rejects a mismatched archive.
- The archive hash was computed from the downloaded official release, not obtained through a separate signed verification channel.
- Runtime location: .tools/love-11.5-win64.
- conf.lua's version field describes compatibility; it does not itself install or lock a runtime.
- Lua target: the LuaJIT/Lua 5.1 environment bundled with this distribution.
- Blender export target: locally installed Blender 5.1, independently recorded by the export report.

## Reference machine

Reference PC: AMD Ryzen 5 5600G; NVIDIA GeForce RTX 3060; 25,601,957,888 bytes OS-reported RAM (approximately 23.84 GiB). Rendered proofs use 1280x800. The final 240-unit idle acquisition/visibility fixture measured 4.820 ms p95 and 7.559 ms maximum per tick. Crowded battle performance and 1080p/60 FPS remain unverified.

## Troubleshooting

Missing runtime: run scripts/setup.ps1. Checksum mismatch: inspect the archive; do not replace the expected checksum just to bypass verification. Use lovec.exe for console output. Run the directory containing main.lua, not main.lua itself.

All scripts locate the repository from their own location, so they work from another working directory. Replay input paths are resolved before changing directory. Tests run without graphics/window/audio and return process exit codes.

The normal game writes replays and screenshots under artifacts in a checkout. A packaged build uses its launch directory for artifacts. The package launcher creates it.
