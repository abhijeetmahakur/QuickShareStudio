# QuickShare Studio 🚀
### Cross-Platform File Sharing, Smart Clipboard & Professional PDF Studio

QuickShare Studio is a complete, production-ready desktop and mobile application designed to solve common academic, laboratory, and developer file-management problems: capturing screenshots across devices, organizing lab workflows into clean Xerox-ready multi-page PDFs, and executing high-speed, verifiable local device-to-device transfers.

---

## 🌟 Key Features

### 1. Professional PDF Studio & Live Xerox Preview
- **3-Panel Desktop Layout**: Left page thumbnails bar, center WYSIWYG live preview canvas with exact paper bounds, and right real-time layout & styling controls.
- **Exact 7 Layout Presets**:
  - `1 Image / Page` (Full page showcase)
  - `2 Images / Page` (1x2 portrait or 2x1 landscape)
  - `3 Images / Page` (3x1 vertical stack)
  - `4 Images / Page` (2x2 grid for lab reports)
  - `6 Images / Page` (3x2 compact overview)
  - `8 Images / Page` (4x2 dense multi-step view)
  - `10 Images / Page` (5x2 dense code index)
  - *Custom Grid*: Freeform rows and columns.
- **Xerox Safe Margins**: Visual printer cutoff guides (5mm / 14pt minimum margin) ensuring no headers or code edges get cut off when printed or photocopied.
- **Live Styling**: Configurable borders, rounded corners, drop shadows, aspect ratio preservation (Contain vs. Crop-to-Fill), background color, header/footer text, and page numbering (`Page X of Y`).
- **Invisible Searchable OCR Text Layer**: Generates standard vector PDF files with selectable and searchable text corresponding to image positions.

### 2. Device-to-Device Sharing & Pairing
- **Zero-Cloud Local Transfers**: Direct transfers over local Wi-Fi / LAN using chunked streaming.
- **Expiring 6-Digit Numeric Code**: 5-minute timed pairing codes with brute-force rate-limiting safeguards.
- **QR Code Pairing**: Instant mobile-to-desktop scanning with JSON payloads (`quickshare://pair?code=...`).
- **Cryptographic File Integrity**: Pre-transfer and post-transfer SHA-256 checksums with short 8-character fingerprints.
- **Resilient Transfers**: Chunked progress tracking with Pause, Resume, and Cancel support.
- **Multi-Device Broadcast**: Send files simultaneously to multiple selected lab peers.

### 3. Screenshot Collection & Session Management
- **Lab Session Folders**: Organize screenshots by session (e.g., `Java Lab Practical 3`, `Python Experiment 5`).
- **Instant Sample Screenshots**: Built-in realistic code terminal and browser screenshots for immediate testing without external files.
- **Automatic Deduplication**: Content hashing prevents duplicate screenshots from polluting lab reports.
- **Drag-and-Drop & Multi-Select**: Reorder images with live preview updates.

### 4. Smart Clipboard Sync
- **Explicit Consent**: Clipboard contents are inspected and previewed prior to broadcast.
- **Text & Media**: Supports plain text, code snippets, URLs, and image data.

### 5. PDF Utilities
- **Merge PDFs**: Combine multiple PDF lab manuals and code outputs into a single document.
- **Split PDFs**: Extract specific page ranges.
- **Compress Profiles**: Web (72 DPI), Normal (150 DPI), and Print (300 DPI) optimizations.

### 6. Security & Privacy
- **Salted SHA-256 PIN Lock**: Protect confidential lab files and transfer history.
- **Private Transfer Mode**: Anonymize device identifiers during discovery.
- **One-Click Cache Purge**: Instantly wipe cached transfers, screenshots, and export buffers.

---

## 🛠 Architecture & Tech Stack

- **Framework**: Flutter 3.47.6 (Dart 3.13.5)
- **State Management**: `Provider` with reactive `TransferEngine`
- **PDF Generation**: `pdf` (vector rendering) & `printing` (cross-platform print dialogs)
- **Security & Hashes**: `crypto` (SHA-256), `uuid` (v4 session tracking)
- **Local Storage**: `shared_preferences`
- **File System**: `file_picker` with cross-platform abstractions

```
lib/
├── app/
│   ├── app_shell.dart              # Responsive navigation (Sidebar / Bottom bar)
│   ├── dashboard_view.dart         # Hub with 10 core modules & quick actions
│   └── theme.dart                  # Curated Dark & Light modern theme
├── core/
│   ├── constants.dart              # Paper sizes (A4, A3, A5, Letter) & tokens
│   └── utils/
│       ├── file_utils.dart         # Platform path sanitization
│       ├── format_utils.dart       # Byte speed & size formatting
│       ├── hash_utils.dart         # SHA-256 cryptographic utilities
│       └── sample_screenshot_generator.dart # In-memory realistic lab captures
├── data/
│   ├── models/                     # Strongly-typed data models
│   └── services/
│       └── transfer_engine.dart    # Singleton transfer, pairing, & discovery engine
└── features/
    ├── clipboard/                  # Universal clipboard view
    ├── file_transfer/              # Send files view with pause/resume
    ├── nearby_devices/             # Local subnet discovery
    ├── pairing/                    # QR & 6-digit PIN pairing view
    ├── pdf_editor/                 # Desktop 3-panel studio & export dialog
    ├── pdf_layout/                 # Geometry & 7 layout preset engines
    ├── pdf_tools/                  # Merge, Split, Compress, OCR
    ├── screenshot_collections/     # Session manager & gallery
    ├── security/                   # PIN lock & cache purge
    ├── templates/                  # 5 pre-configured lab templates
    └── transfer_history/           # Audit trail & resend view
```

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.47+ (`flutter --version`)
- Chrome or Edge browser (for Web build) or Visual Studio C++ (for Windows desktop native)

### Running Locally

```bash
# Run unit and widget tests
flutter test

# Run code analysis
flutter analyze

# Launch on Chrome
flutter run -d chrome

# Build production web bundle
flutter build web
```

### Running the Production Web Bundle
```bash
python -m http.server 8080 --directory build/web
# Open http://localhost:8080 in your browser
```

---

## 🧪 Verification & Test Suite

The test suite in [`test/widget_test.dart`](file:///test/widget_test.dart) tests:
1. **PDF Layout Presets**: Verifies all 7 presets (1, 2, 3, 4, 6, 8, 10 images) calculate correct row/column bounds and safe margins.
2. **Cryptographic Integrity**: Validates SHA-256 checksum determinism and 8-character fingerprints.
3. **Pairing Session**: Validates 6-digit numeric code generation, countdown expiry, and QR code URI format (`quickshare://pair?code=...`).
4. **App Smoke Test**: Pumps full application shell, checks Dashboard presence, responsive layout, and clean lifecycle disposal.

---

## 📄 License
MIT License. Built for seamless cross-platform computer lab and developer workflows.

