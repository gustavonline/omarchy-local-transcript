# Local Transcript for Omarchy

Local Transcript is a local-first Omarchy bar widget for recording, transcribing,
annotating, and summarizing meetings, videos, lectures, podcasts, and other
spoken computer audio. Audio and inference stay on your computer. Network access
is used only when you explicitly download a model.

## What it does

- Captures computer audio and microphone input through PipeWire/PulseAudio
- Uses Voxtype meeting mode for continuous multilingual speech-to-text
- Labels microphone audio as `You` and computer audio as `Remote`
- Adds timestamped manual annotations while recording
- Optionally saves a compressed `recording.ogg`
- Exports a portable Markdown transcript plus structured transcript JSON
- Optionally creates a same-language local summary with Ollama
- Can suggest transcription when selected installed apps begin using audio
- Discovers desktop and Omarchy web apps automatically in a searchable picker

## Recommended local models

Speech recognition uses the multilingual—not `.en`—Whisper variants:

| Model | Download | Guidance |
|---|---:|---|
| `base` | 142 MB | Lightest option, lower accuracy |
| `small` | 466 MB | Recommended balance for general Omarchy computers |
| `large-v3-turbo` | 1.6 GB | Better accuracy, heavier memory/compute use |

The optional summary uses Ollama:

| Model | Download | Guidance |
|---|---:|---|
| Disabled | 0 | Markdown transcript without AI summary |
| `qwen3:1.7b` | 1.4 GB | Light summary option |
| `qwen3:4b-instruct` | 2.5 GB | Recommended quality/size balance |

Qwen thinking is disabled for this summarization task. The summary prompt detects
the transcript language, writes in the same language, respects `You`/`Remote`
source labels, and avoids inventing speaker identities or meeting decisions.

## Install

```bash
omarchy plugin add /path/to/omarchy-local-transcript --enable --yes
```

Open the document icon in the bar. The main panel is intentionally limited to
title, start/stop, pause, quick annotations, and opening the transcript folder.
Use the cog button for storage, model downloads, audio retention, and reminders.

The title is optional. If it is blank, Local Transcript uses active local audio
metadata and selected web-app window context to produce a useful title such as
`YouTube` or `Spotify + Zoom`. A manually entered title always takes priority.
When an app cannot be identified reliably, the neutral name `Transcript` is used.

## App-aware reminders

The settings page contains a searchable multi-select populated from the actual
`.desktop` applications installed on the computer, including Omarchy web apps.
For example, you can select Zoom, Discord, Zen Browser, or YouTube independently.

Detection checks local PipeWire recording/playback metadata and Hyprland window
metadata. It never inspects audio content. A notification requires two consecutive
detections and then has a 30-minute cooldown. Leaving Discord or Zen Browser
unchecked prevents reminders from those apps.

You do not need to enable an app to transcribe it manually. For a YouTube video,
start Local Transcript and play the video; its computer audio is captured as
`Remote`.

## Output

Each recording gets a portable folder:

```text
Transcripts/
  2026-08-19-143000-video-title/
    2026-08-19-143000-video-title.md
    transcript.json
    manual-notes.jsonl
    recording.ogg       # optional
```

The main Markdown file contains YAML frontmatter, an optional summary, key points,
decisions and checkbox actions, manual annotations, relative source-file links,
detected source names, and a timestamped speaker/source transcript. Both its
folder and filename begin with local date and time; an explicit title or up to
four detected audio sources form the remainder of the name.

Voxtype's crash-resistant internal data is stored in the hidden `.voxtype-data`
folder inside the selected output directory.

## Privacy and consent

No recording content is sent to a cloud service. The plugin starts an Ollama user
service bound to `127.0.0.1` only after a summary model download. The red bar icon
makes active capture visible. You remain responsible for informing participants
and obtaining any consent required by local rules or your workplace.

## Development

```bash
omarchy plugin validate .
python3 -m py_compile local-transcript
python3 tests/test_backend.py
```

Settings live in `~/.config/omarchy/local-transcript.json`. Before the first
Voxtype edit, the previous Voxtype configuration is backed up under
`~/.local/share/omarchy-local-transcript/voxtype-config.before-local-transcript.toml`.

## Remove

```bash
omarchy plugin remove io.github.gustavonline.local-transcript
```

Removing the plugin does not delete transcripts, downloaded models, or the
optional user-level Ollama service.

## License

MIT. See [NOTICE](NOTICE) for attribution.
