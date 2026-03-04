# Stash

A tiny macOS menubar app that lets you store up to 10 text clips and paste any of them instantly with **Ctrl+1** through **Ctrl+0**.

No fluff. Stash text, paste it later.

## Usage

- **Ctrl+1** to **Ctrl+9** — paste clips 1–9
- **Ctrl+0** — paste clip 10
- **Cmd+V** — normal paste, unaffected

Manage clips from the menubar icon → "Manage Clips".

## Install

Download `Stash.zip` from [Releases](https://github.com/hjpithadia/stash/releases), unzip, and drag to Applications.

Since Stash is open-source and not signed with an Apple Developer ID, macOS Gatekeeper will block it on first launch. This is normal for any app downloaded outside the App Store that isn't notarized. Run this once in Terminal to clear the quarantine flag:

```bash
xattr -cr ~/Downloads/Stash.app
```

Then open normally. You'll also need to grant Accessibility permission (System Settings → Privacy & Security → Accessibility) for the keyboard shortcuts to work.

## Build from source

```bash
swiftc -swift-version 5 -O -o Stash main.swift -framework AppKit -framework CoreGraphics
```

Or use the bundle script to create a `.app`:

```bash
./scripts/bundle.sh
```


## License

Apache License 2.0
