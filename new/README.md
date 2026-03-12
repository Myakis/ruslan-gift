# Wplan Auto (ElectroBun)

## Development

```bash
bun install
bun run dev
```

## Release builds

```bash
# macOS (arm64 + x64)
bun run build:mac

# Windows (x64)
bun run build:win

# both
bun run build:release
```

Artifacts are generated in `artifacts/`.
