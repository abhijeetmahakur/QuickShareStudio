# QuickShare Studio - Development Workflow & Hot Reload Guide

This guide details how to develop **QuickShare Studio** locally with instant **Hot Reload**, automated **Hot Restart** fallback, and resilient error recovery.

---

## ⚡ Overview: Dev Mode vs. Packaged App

| Mode | Entrypoint | Behavior on Code Save | Requires Restart / Rebuild? |
| :--- | :--- | :--- | :--- |
| **Local Development** | [`QuickShareDev.bat`](QuickShareDev.bat)<br>[`scripts/dev_runner.py`](scripts/dev_runner.py)<br>VS Code / Antigravity (`F5`) | **Hot Reload** reflects UI & logic changes instantly in the running app window. | Only when modifying constructors, state initializers, or native/pubspec assets. |
| **Packaged Release** | [`QuickShare.bat`](QuickShare.bat)<br>`QuickShareStudio.exe` | **Static compiled bundle**. Edits in `lib/` do not affect the running release. | Rebuilding with `flutter build web` or running [`scripts/install_quickshare.ps1`](scripts/install_quickshare.ps1). |

> [!NOTE]
> Normal source-code edits do **not** trigger in-app update prompts or update alerts. In-app update notifications are strictly reserved for production installs when a published release package is deployed.

---

## 🚀 Starting the App in Development Mode

You can launch QuickShare Studio in development mode using any of the following methods:

### Method 1: Double-Click Dev Launcher (Recommended on Windows)
Double-click [`QuickShareDev.bat`](QuickShareDev.bat) located in the project root folder.
* Automatically selects Google Chrome (or Edge/Windows desktop if specified: `QuickShareDev.bat edge` or `QuickShareDev.bat windows`).
* Starts Flutter connected to the active Dart VM service and begins monitoring all source files.

### Method 2: PowerShell Dev Script
From PowerShell in the project folder:
```powershell
# Run with default browser (Chrome)
.\scripts\dev.ps1

# Or target Microsoft Edge
.\scripts\dev.ps1 -Device edge

# Or target native Windows desktop
.\scripts\dev.ps1 -Device windows
```

### Method 3: VS Code / Antigravity IDE
The repository includes `.vscode/launch.json` and `.vscode/settings.json` configured for Hot Reload on Save:
1. Open the project folder in VS Code or Antigravity IDE.
2. Press **`F5`** or go to the **Run & Debug** panel and choose:
   - **QuickShare Studio (Chrome - Live Dev)**
   - **QuickShare Studio (Edge - Live Dev)**
   - **QuickShare Studio (Windows Desktop - Live Dev)**
3. Whenever you save a `.dart` file (`Ctrl+S`), the IDE automatically triggers Hot Reload into the running app.

### Method 4: Terminal Command Line
```bash
# Intelligent watcher runner (auto hot reload & hot restart fallback)
python scripts/dev_runner.py -d chrome

# Or standard Flutter CLI
flutter run -d chrome
```

---

## 🔄 How Code Changes are Applied

### 1. Hot Reload (Automatic on File Save)
When you save changes to any Dart file in `lib/`:
* The watcher detects the change, debounces rapid edits (300ms), and sends the hot reload signal (`r`) to Flutter.
* Flutter injects the updated source code into the running Dart VM.
* The widget tree is rebuilt with the new UI styles, colors, text, or layout changes.
* **Application state is preserved**: Your current screen, navigation position, active inputs, and loaded items remain unchanged.

### 2. Automatic Hot Restart Fallback
Certain changes cannot be patched into existing running instances by Hot Reload (such as modifying static variables, `initState()` logic, or adding new routes/classes).
* The dev runner monitors the Flutter compiler output. If hot reload is rejected, or if you modify `pubspec.yaml`, `assets/`, or `web/index.html`, it automatically triggers a **Hot Restart** (`R`).
* Hot restart reinitializes the app state and restarts the Dart code execution in ~1 second, without closing the browser window or terminating the Flutter process.

### 3. Interactive Keyboard Controls
While the runner is active in your terminal, you can send manual commands at any time:
* **`r`** : Manually trigger Hot Reload.
* **`R`** : Manually trigger Hot Restart.
* **`h`** : Show available commands and status.
* **`c`** : Clear console screen.
* **`q`** : Cleanly terminate the Flutter application and exit.

---

## 🛡️ Compilation Error Resilience

If you introduce a syntax error, missing import, or type mismatch while editing:
1. **The app will NOT crash or close.** The running instance remains completely functional on the last valid build state.
2. The dev runner captures the error and displays a clear diagnostic box in your terminal:
   ```
   ╔══════════════════════════════════════════════════════════════════════╗
   ║                      COMPILATION ERROR DETECTED                      ║
   ╠══════════════════════════════════════════════════════════════════════╣
   ║  QuickShare Studio remains RUNNING on the last working state.        ║
   ║  The running app was not terminated or closed.                       ║
   ╠──────────────────────────────────────────────────────────────────────╣
     ! lib/features/pdf_editor/pdf_editor_view.dart:120:15: Error: ...
   ╠══════════════════════════════════════════════════════════════════════╣
     Fix the syntax/type error in your editor and save to hot-reload!     
   ╚══════════════════════════════════════════════════════════════════════╝
   ```
3. Once you correct the error in your editor and press `Ctrl+S`, the runner re-compiles and reloads the fixed code immediately.

---

## 📋 Change Type Matrix: Hot Reload vs. Restart vs. Rebuild

| Change Category | Examples | Action Required | Preserves State? |
| :--- | :--- | :--- | :--- |
| **Widget UI & Styling** | Modifying widget `build()` methods, colors, padding, typography, icons, layout constraints, theme tokens. | **Hot Reload** (`r`) *(Automatic on save)* | **Yes** |
| **Business Logic** | Helper functions, calculation methods, formatting utilities, event handlers. | **Hot Reload** (`r`) *(Automatic on save)* | **Yes** |
| **State Initialization** | Modifying `initState()`, constructor defaults, or `dispose()` hooks. | **Hot Restart** (`R`) *(Automatic fallback)* | No (Reinitializes state) |
| **Static & Global Variables** | Modifying `static const` fields, top-level constants, global singletons. | **Hot Restart** (`R`) *(Automatic fallback)* | No (Reinitializes state) |
| **New Classes & Enums** | Adding a new widget class, model enum, or route definition. | **Hot Restart** (`R`) *(Automatic fallback)* | No (Reinitializes state) |
| **Assets & Fonts** | Adding image files to `assets/` or updating font declarations in `pubspec.yaml`. | **Hot Restart** (`R`) *(Automatic)* | No |
| **New Dependencies** | Adding a new package to `dependencies:` in `pubspec.yaml`. | **Full Rebuild** (`flutter pub get` + rerun runner) | No (Process restarts) |
| **Native Platform Code** | Modifying Windows C++ runner code (`windows/runner/`) or Android manifest. | **Full Rebuild** (`flutter run -d windows` / `flutter run -d android`) | No |
| **Web Entrypoint Shell** | Modifying `web/index.html` headers, scripts, or meta tags. | **Hot Restart** or **Browser Refresh** (`Ctrl+F5`) | No |

---

## 📦 Updating the Packaged Release

When you are ready to publish or update the packaged/installed app on your machine:
```powershell
# 1. Compile production bundle
flutter build web --release

# 2. Update local installation
.\scripts\install_quickshare.ps1
```
The installed app at `$LOCALAPPDATA\Programs\QuickShare Studio` will then reflect the latest build.
