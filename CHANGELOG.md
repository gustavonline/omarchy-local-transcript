# Changelog

## 0.3.0 — 2026-08-19

- Refined panel and settings copy around recordings, transcripts, and models
- Removed implementation and privacy slogans from the primary interface
- Made model readiness update immediately when a different model is selected
- Hardened summaries against instructions embedded in transcript content
- Standardized user-facing recording errors and command override names

## 0.2.1 — 2026-08-19

- Open the configured transcript folder directly from the main panel
- Use date, time, an optional title, and detected active audio sources for names
- Give the primary Markdown document the same meaningful name as its folder
- Compact installed-model status rows and add breathing room below settings

## 0.2.0 — 2026-08-19

- Renamed the plugin to Local Transcript and expanded it beyond meetings
- Added searchable multi-select discovery of installed desktop and web apps
- Detects selected apps through active microphone, playback, and window metadata
- Replaced the crowded setup screen with a compact main view and separate settings page
- Replaced model cycling buttons with native dropdowns and automatic language detection
- Updated the recommended summary model to Qwen 3 4B Instruct
- Added transcript-aware, same-language summaries for meetings, videos, podcasts, and lectures
- Renamed the main portable Markdown document to `transcript.md`

## 0.1.0 — 2026-08-18

- Initial local-only meeting capture workflow
- Multilingual Voxtype model setup and download controls
- Local Ollama summary model selection and download controls
- Microphone plus desktop audio transcription with simple attribution
- Optional compressed audio recording
- Standard Markdown, YAML frontmatter, JSON transcript, and manual notes
- Configurable meeting-app detection with custom application names
