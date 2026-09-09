# Clipvault

A small native macOS menu-bar app that stores a text clipboard history locally, with no count limit imposed by the app.

## Install and run

```sh
cd /Users/Kenn/.codex/.chatgpt-projects/g-p-6a915e7dc6ac8191a90f1e26b00f7651/clipboard-vault
chmod +x build.sh
./build.sh
```

Opening the app immediately shows its clipboard window. It also stays running as a small clipboard icon in the menu bar (it has no Dock icon). Copy text normally with `⌘C` (or any other macOS copy route), then press `⌘⇧V` or `⌘⌥V` to search and select an earlier item. Selecting it puts it back on the clipboard and pastes it into the previously used app.

On first paste, macOS will ask you to allow Accessibility access. Turn it on in **System Settings → Privacy & Security → Accessibility** for Clipvault. This permission is required for any macOS app to synthesize the final `⌘V` into another app.

History is saved locally, only for this macOS account, at:

`~/Library/Application Support/Clipboard Vault/history.json`

The app records plain text. It deliberately does not capture files, images, passwords from secure fields, or rich formatting. Use **Clear All History** from the menu-bar menu to remove its saved history.
