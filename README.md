# Clipvault

Clipvault is a private, local macOS clipboard-history app. It captures plain-text copies, keeps the history on your Mac, and provides a fast menu-bar picker for reusing an item.

## Requirements

- macOS 13 Ventura or later
- Accessibility permission, needed for Clipvault to paste the selected item back into the app you were using

## Install

### Homebrew (recommended)

```sh
brew tap kennethjohnbalgos/clipvault-app https://github.com/kennethjohnbalgos/clipvault-app
brew install --cask kennethjohnbalgos/clipvault-app/clipvault
```

To update Clipvault later:

```sh
brew upgrade --cask kennethjohnbalgos/clipvault-app/clipvault
```

Homebrew updates replace the app bundle only. Your clipboard history remains at `~/Library/Application Support/Clipboard Vault/history.json`.

To uninstall the app while keeping your history:

```sh
brew uninstall --cask kennethjohnbalgos/clipvault-app/clipvault
```

To remove the app **and** all saved history deliberately:

```sh
brew uninstall --cask --zap kennethjohnbalgos/clipvault-app/clipvault
```

### Manual installation

1. Download the `Clipvault-1.0.0.zip` asset from the latest GitHub release and unzip it.
2. Drag **`Clipvault.app`** into your **Applications** folder.
3. Open Clipvault. The history window appears immediately and a clipboard icon remains in the menu bar.
4. If macOS warns that the app is from an unidentified developer, Control-click **Clipvault.app**, choose **Open**, then choose **Open** again.
5. When macOS asks, allow Clipvault in **System Settings → Privacy & Security → Accessibility**. You can also enable this later; Clipvault needs it to use global shortcuts and paste into another app.

Clipvault is distributed as an unsigned local app bundle. The included app is ready to use; no developer tools are required. If you prefer to build it yourself, run `./build.sh` in this folder (requires Xcode Command Line Tools).

## Use Clipvault

- Copy text normally with **⌘C**. Clipvault records plain-text clipboard changes locally.
- Click Clipvault’s menu-bar clipboard icon to toggle history open or closed.
- Press **⌘⇧V** or **⌘⌥V** anywhere to open history.
- Click an item to select it; double-click it to copy the text, close Clipvault, and attempt to paste into the previously active field.
- Press **Return** or **Enter** when an item is selected to do the same.
- To paste by keyboard: hold the shortcut modifiers, press **V** again to select the first item, then press **V** again to advance. Releasing either modifier pastes the selected item into the previously active app.
- Use **↑** and **↓** to move through the visible list. Press **Delete** to remove a selected non-pinned item.
- Press **Esc** to close the window.
- Use the gear menu at the bottom-left to import or export history, enable **Start at login**, or quit. Import merges a Clipvault JSON export with your existing history.

## Pins

Use the orange pin icon to pin an item. Clipvault requires a title for every pin. The picker has two tabs:

- **Recent** contains the latest copied or reused records, including pinned records while they are recent.
- **Pinned** contains all titled pins.

Right-click a pinned item to rename or unpin it. Pinned items are protected from deletion. Right-click a regular item to delete it.

## Privacy and data

Clipvault stores its history only for the current macOS account at:

`~/Library/Application Support/Clipboard Vault/history.json`

It records plain text only; it does not capture files, images, rich formatting, or content that macOS does not place on the standard text clipboard. Your history is not sent anywhere.
