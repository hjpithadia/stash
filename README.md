# Stash

A tiny macOS menubar app that lets you store up to 10 text clips and paste any of them instantly with **Ctrl+1** through **Ctrl+0**.

No fluff. Stash text, paste it later.

## Usage

- **Ctrl+1** to **Ctrl+9** — paste clips 1–9
- **Ctrl+0** — paste clip 10
- **Cmd+V** — normal paste, unaffected

Manage clips from the menubar icon → "Manage Clips".

## Build

```bash
swiftc -swift-version 5 -O -o Stash main.swift -framework AppKit -framework CoreGraphics
```

Or use the bundle script to create a `.app`:

```bash
./scripts/bundle.sh
```

## Requirements

- macOS 14+
- Accessibility permission (System Settings → Privacy & Security → Accessibility)

## License

Apache License 2.0
