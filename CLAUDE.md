# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**MarkAny** — an Electron desktop app that converts PDF, Word, Excel, PowerPoint, and HTML documents to Markdown. Runs a Python HTTP backend for conversion, with image extraction and Tesseract OCR for scanned PDFs. All UI text is in Chinese (Simplified).

## Tech Stack

- **Electron 29 + React 18 + TypeScript** — main process, preload, renderer
- **Vite 5 + vite-plugin-electron** — build tooling for renderer and main process
- **Python 3.12** — HTTP backend service (port 8765) with PyMuPDF, MarkItDown (Microsoft), OpenCV, Tesseract OCR
- **Vitest + @testing-library/react** — renderer tests
- **pytest** — Python backend tests
- **PyInstaller** — bundles Python backend; **electron-builder** — packages desktop app (DMG on macOS, NSIS on Windows)
- Dual-platform support: Windows (`--win` or auto-detect) and macOS (`--mac` or auto-detect); platform detection via `process.platform` in Electron and `platform.system()` in Python

## Commands

```bash
# Development
npm run dev                # Start Vite dev server (localhost:5173)

# Testing
npm run test               # Run Vitest (renderer)
npm run test:watch         # Vitest in watch mode
npm run test:python        # Run pytest on Python backend (from src/python/)
npm run test:all           # Run both Vitest and pytest

# Building
npm run build              # Full production build (tesseract setup + Python exe + TS compile + electron-builder)
npm run build:dir          # Build unpacked directory (no installer)
npm run build:no-python    # Build without recompiling Python backend
npm run python:build       # Build Python backend with PyInstaller only
npm run tesseract:setup    # Assemble portable Tesseract OCR bundle
```

To run a single renderer test: `npx vitest run src/renderer/__tests__/ActionBar.test.tsx`
To run a single Python test: `cd src/python && python3 -m pytest tests/test_converters.py -v`
To run macOS DMG build: `npm run build:dir:mac` (no Python backend) or `npm run build:mac` (full build)

## Architecture

Three-tier app communicating via IPC and HTTP:

```
Renderer (React SPA)
  ↕ window.electronAPI (IPC via contextBridge)
Main Process (Electron)
  ↕ HTTP POST to 127.0.0.1:8765
Python Backend (http.server)
```

- **`src/main/index.ts`** — creates frameless BrowserWindow (900x700), starts Python service, loads renderer
- **`src/main/ipc-handlers.ts`** — spawns Python process, registers IPC handlers, bridges renderer ↔ Python HTTP API
- **`src/main/preload.ts`** — exposes `electronAPI` to renderer: `selectFiles`, `selectDirectory`, `convertFile`, `getPathForFile`, `minimize`, `maximize`, `close`
- **`src/renderer/App.tsx`** — single component managing all state (file queue, format, progress); target format is hardcoded to Markdown
- **`src/python/main.py`** — HTTP server with `GET /` (health check) and `POST /` (convert file, returns JSON)
- **`src/python/converters/pdf_converter.py`** — PDF via PyMuPDF; auto-detects scanned pages, renders at 300 DPI, applies OpenCV enhancement (CLAHE, adaptive binarization), then Tesseract OCR (`chi_sim+eng`)
- **`src/python/converters/markitdown_converter.py`** — DOCX/XLSX/PPTX/HTML/TXT via Microsoft MarkItDown
- **`src/python/ocr/tesseract_ocr.py`** — Tesseract wrapper; locates bundled or system install; uses `TESSDATA_PREFIX` env var for data path
- **`src/python/utils/image_extractor.py`** — extracts embedded images from PDF/DOCX/PPTX to `images/` subdirectory

## Key Conventions

- TypeScript strict mode with `noUnusedLocals`, `noUnusedParameters`; target ES2020, JSX automatic runtime (`react-jsx`)
- Python uses type hints with `str | None` syntax (3.10+); comments are mixed Chinese/English
- Dark theme: backgrounds `#181818`/`#252525`, accent indigo `#6366f1`/`#818cf8`; all CSS in single `App.css`
- macOS uses `titleBarStyle: 'hiddenInset'` with native traffic-light buttons; Windows uses `frame: false` with custom title bar controls
- Frameless window with custom `TitleBar` component on Windows; hidden on macOS (native buttons used)
- No ESLint, Prettier, or Python linter configured
- Sample test files in `test_files/` at project root

## Known Issues

- `src/python/markdown/to_document.py` is imported in `__init__.py` but the file does not exist — the reverse conversion (Markdown → DOCX/PPTX/HTML/PDF) feature is incomplete/removed
