# Clipvault

Clipvault is a private, local macOS clipboard-history app. It captures plain-text copies, keeps the history on your Mac, and provides a fast menu-bar picker for reusing an item.

## Requirements

- macOS 13 Ventura or later
- Accessibility permission, needed for Clipvault to paste the selected item back into the app you were using

## Install

1. Download this repository as a ZIP from GitHub and unzip it, or clone it.
2. Drag **`Clipvault.app`** into your **Applications** folder.
3. Open Clipvault. The history window appears immediately and a clipboard icon remains in the menu bar.
4. If macOS warns that the app is from an unidentified developer, Control-click **Clipvault.app**, choose **Open**, then choose **Open** again.
5. When macOS asks, allow Clipvault in **System Settings → Privacy & Security → Accessibility**. You can also enable this later; Clipvault needs it to use global shortcuts and paste into another app.

Clipvault is distributed as an unsigned local app bundle. The included app is ready to use; no developer tools are required. If you prefer to build it yourself, run `./build.sh` in this folder (requires Xcode Command Line Tools).

## Use Clipvault

- Copy text normally with **⌘C**. Clipvault records plain-text clipboard changes locally.
- Click Clipvault’s menu-bar clipboard icon to open history.
- Press **⌘⇧V** or **⌘⌥V** anywhere to open history.
- Click an item to select it; double-click it to copy its text back to the clipboard without pasting.
- To paste by keyboard: hold the shortcut modifiers, press **V** again to select the first item, then press **V** again to advance. Releasing either modifier pastes the selected item into the previously active app.
- Use **↑** and **↓** to move through the visible list. Press **Delete** to remove a selected non-pinned item.
- Press **Esc** to close the window. The red **Quit** button stops Clipvault entirely after confirmation.
- Enable **Open at login** at the bottom of the window to start Clipvault automatically.

## Pins

Use the orange pin icon to pin an item. Clipvault requires a title for every pin. The picker has two tabs:

- **Recent** contains the latest copied or reused records, including pinned records while they are recent.
- **Pinned** contains all titled pins.

Right-click a pinned item to rename or unpin it. Pinned items are protected from deletion. Right-click a regular item to delete it.

## Privacy and data

Clipvault stores its history only for the current macOS account at:

`~/Library/Application Support/Clipboard Vault/history.json`

It records plain text only; it does not capture files, images, rich formatting, or content that macOS does not place on the standard text clipboard. Your history is not sent anywhere.
