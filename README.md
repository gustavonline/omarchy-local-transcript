# Local Meeting for Omarchy

A local-first Omarchy bar widget for recording, transcribing, annotating, and
summarizing meetings. Audio and inference stay on your computer. The only
network activity is an explicit, one-time model download initiated by you.

## What it does

- Captures microphone and desktop audio through PipeWire/PulseAudio
- Uses Voxtype meeting mode for continuous multilingual speech-to-text
- Separates your microphone (`You`) from desktop audio (`Remote`)
- Adds timestamped manual notes during the meeting
- Optionally saves a compressed `recording.ogg`
- Exports a standard Markdown meeting note and structured transcript JSON
- Optionally creates a local AI summary with Ollama
- Detects likely meetings from active microphone clients and window metadata
- Lets you enable, disable, or add meeting apps used by the detector

## Local model choices

Speech-to-text models are downloaded and run by Voxtype:

| Model | Approximate download | Use case |
|---|---:|---|
| `base` | 142 MB | Very light, lower accuracy |
| `small` | 466 MB | Recommended multilingual default |
| `large-v3-turbo` | 1.6 GB | Best accuracy on capable hardware |

Summary models are downloaded and run by Ollama:

| Model | Approximate download | Use case |
|---|---:|---|
| `gemma3:1b` | 815 MB | Smallest useful multilingual option |
| `qwen3.5:2b` | 2.7 GB | Recommended quality/size balance |
| `qwen3.5:4b` | 3.4 GB | Better summaries, more memory |

AI summaries can be disabled entirely. Cloud model tags are blocked by the
backend. The Ollama API is bound to `127.0.0.1` only.

## Requirements

- Omarchy with the Quickshell plugin system
- Voxtype 0.7.5 or newer
- PipeWire with PulseAudio compatibility (`pactl`)
- Python 3
- `ffmpeg` when saving the actual audio file
- Ollama only when AI summaries are enabled

## Install

From a local checkout:

```bash
omarchy plugin add /path/to/omarchy-local-meeting --enable --yes
```

Open the bar widget and complete **Setup**. Choose a folder, speech model,
language mode, summary model, audio retention preference, and meeting apps.
Downloads only begin when you press the corresponding download button.

## Meeting detection

The widget polls local PipeWire metadata while loaded. A reminder is shown
only when an enabled app is actively using the microphone for two consecutive
checks. Notifications have a 30-minute cooldown.

Built-in toggles cover Zoom, Microsoft Teams, Slack, Google Meet, Discord,
Buzz, Webex, Jitsi, and generic browser calls. Add other app or process names
as a comma-separated list. Disable Discord or generic browser detection if
those cause reminders during gaming or voice chat.

Detection reads process/application metadata and Hyprland window titles. It
does not capture or inspect conversation audio.

## Output

Each meeting gets a portable folder:

```text
Meeting Notes/
  2026-08-18-143000-project-kickoff/
    meeting.md
    transcript.json
    manual-notes.jsonl
    recording.ogg       # optional
```

`meeting.md` uses standard Markdown and YAML frontmatter, with these sections:

- Summary, key points, decisions, and checkbox action items (optional)
- Manual notes
- Relative links to the structured transcript and optional recording
- Timestamped speaker transcript

Voxtype's internal crash-resistant meeting data is kept in the hidden
`.voxtype-data` folder inside the selected meeting directory.

## Privacy and recording consent

No meeting content is sent to a cloud service. Model downloads contact the
Voxtype/Ollama model registries, but inference happens locally afterwards.
The red bar icon makes active capture visible. You remain responsible for
informing participants and obtaining any consent required by your workplace
or local rules.

## Development

```bash
omarchy plugin validate .
python3 -m py_compile local-meeting
python3 tests/test_backend.py
```

The backend stores plugin settings in
`~/.config/omarchy/local-meeting.json`. Before its first Voxtype edit it saves
a copy of the prior configuration under
`~/.local/share/omarchy-local-meeting/voxtype-config.before-local-meeting.toml`.

## Remove

```bash
omarchy plugin remove io.github.gustavonline.local-meeting
```

Removing the plugin does not delete meeting folders, downloaded models, or
the optional user-level Ollama service created after a model download.

## License

MIT. See [NOTICE](NOTICE) for attribution.
