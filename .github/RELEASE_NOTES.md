## Unofficial build — please read

This DMG is **not signed or notarized** (this fork has no paid Apple Developer ID). It is
only *ad-hoc* signed, so macOS Gatekeeper blocks it on first launch with
*"Stats can't be opened because Apple cannot check it for malicious software."*

### How to open it

Clear the download quarantine once:

```bash
xattr -dr com.apple.quarantine /Applications/Stats.app
```

…or try to open it, then go to **System Settings → Privacy & Security** and click
**Open Anyway**.

### ⚠️ Do not let Stats auto-update

Stats' built-in updater points at the **upstream** project (`exelban/stats`). If you let it
update, it installs the **official** build, which does **not** contain the
combined-modules click-routing fix — the bug comes back. To stay on the fixed build:

- Keep **Settings → Update interval** set to **Silent** (the default), and
- Re-download this DMG after any update.

The in-app updater will never offer these `-fix` releases — only upstream's.
