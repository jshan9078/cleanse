# Cleanse

A tiny native macOS app for triaging screenshots. It finds every image file whose
name starts with `Screenshot` in your Desktop, Downloads, Documents, and Pictures
folders and lets you review and delete them fast:

- **Grid view** — click thumbnails to select several, then delete them all at once
  (with a confirmation dialog).
- **Carousel view** — step through screenshots full-size with the arrow keys or
  on-screen buttons, deleting as you go.

Deleted files are moved to the Trash, not permanently erased.

## Architecture

Single-file SwiftUI app with no dependencies — the whole app lives in
[`main.swift`](main.swift):

- **`Library`** (`ObservableObject`) — the entire app state: scans the four folders
  for `Screenshot*` image files, caches downsampled thumbnails (via `ImageIO`),
  tracks the grid selection and carousel index, and moves files to the Trash with
  `FileManager.trashItem`.
- **`ContentView`** — window chrome: a Grid/Carousel toolbar switcher, refresh
  button, live count subtitle, and the delete-confirmation dialog.
- **`GridScreen` / `CarouselScreen`** — the two view modes, both rendering directly
  from the shared `Library`.

## Building

Requires Xcode command-line tools (uses `swiftc` directly, no Xcode project):

```sh
./build.sh
open Cleanse.app
```

`build.sh` compiles `main.swift`, assembles the `Cleanse.app` bundle with
`Info.plist`, and ad-hoc signs it. macOS will ask once for permission to access
each scanned folder.
