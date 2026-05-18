# Lapee ARM

Raspberry Pi 4 / ARM64 working tree for LapEE.

- `upstream-lapee/` is the imported LapEE source from the Permagit/Arweave
  `lapee` repository.
- `ARM/` contains the Raspberry Pi OS / Raspbian ARM64 port layer, build
  scripts, config, and systemd service.
- `tools/import-permagit.mjs` is the repeatable importer used to pull the
  upstream source from Permagit snapshots.

Start with [ARM/README.md](ARM/README.md).
