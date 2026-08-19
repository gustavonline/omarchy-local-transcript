#!/usr/bin/env python3

import importlib.machinery
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_backend():
    loader = importlib.machinery.SourceFileLoader("local_transcript", str(ROOT / "local-transcript"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.module = load_backend()
        self.temp = tempfile.TemporaryDirectory()
        base = Path(self.temp.name)
        self.module.DATA_DIR = base / "data"
        self.module.CONFIG_DIR = base / "config/omarchy"
        self.module.CONFIG_PATH = self.module.CONFIG_DIR / "local-transcript.json"
        self.module.VOXTYPE_CONFIG = base / "config/voxtype/config.toml"
        self.module.VOXTYPE_MODELS = base / "models"
        self.module.ACTIVE_PATH = self.module.DATA_DIR / "active.json"
        self.module.LAST_PATH = self.module.DATA_DIR / "last.json"
        self.module.RUNTIME_STATE = base / "runtime/voxtype/meeting_state"

    def tearDown(self):
        self.temp.cleanup()

    def test_toml_update_keeps_keys_in_their_sections(self):
        path = self.module.VOXTYPE_CONFIG
        path.parent.mkdir(parents=True)
        path.write_text(
            '[whisper]\nmodel = "base.en"\n\n[meeting.audio]\nsource = "mic"\n\n[osd]\nenabled = true\n',
            encoding="utf-8",
        )
        self.module.update_toml(
            path,
            {
                "whisper": {"model": "small", "language": "auto"},
                "meeting.audio": {"loopback_device": "auto", "echo_cancel": "auto"},
            },
            remove={"meeting.audio": {"source"}},
        )
        text = path.read_text(encoding="utf-8")
        self.assertIn('[whisper]\nmodel = "small"\nlanguage = "auto"', text)
        self.assertIn('[meeting.audio]\nloopback_device = "auto"\necho_cancel = "auto"', text)
        self.assertNotIn('source = "mic"', text)
        self.assertIn('[osd]\nenabled = true', text)

    def test_markdown_document_is_portable_and_generic(self):
        session = Path(self.temp.name) / "transcript"
        session.mkdir()
        (session / "transcript.json").write_text("{}\n", encoding="utf-8")
        active = {
            "title": "Dansk video",
            "sources": ["YouTube"],
            "file_stem": "2026-08-19-143000-youtube",
            "started_at": "2026-08-19T14:30:00+02:00",
            "session_dir": str(session),
        }
        self.module.atomic_json(self.module.CONFIG_PATH, {
            **self.module.default_config(),
            "sttModel": "small",
            "summaryModel": "qwen3:4b-instruct",
        })
        (session / "manual-notes.jsonl").write_text(
            json.dumps({"timestamp": "2026-08-19T14:31:00+02:00", "author": "Me", "note": "Vigtig pointe"}) + "\n",
            encoding="utf-8",
        )
        output = self.module.finish_document(
            active,
            "## Summary\n\nKort dansk resumé.",
            "# Dansk video\n\n## Meeting Info\n\n- **Duration:** 1m\n\n## Transcript\n\n*[00:01]* Remote: Hej.\n",
            {},
        )
        text = output.read_text(encoding="utf-8")
        self.assertEqual(output.name, "2026-08-19-143000-youtube.md")
        self.assertIn("tags: [transcript]", text)
        self.assertIn('sources: ["YouTube"]', text)
        self.assertIn("## Manual annotations", text)
        self.assertIn("- **14:31 — Me:** Vigtig pointe", text)
        self.assertIn("[Structured transcript](transcript.json)", text)
        self.assertIn("## Recording info", text)
        self.assertNotIn("## Meeting Info", text)
        self.assertEqual(text.count("# Dansk video"), 1)

    def test_recording_name_prefers_title_then_multiple_sources(self):
        started = self.module.datetime.fromisoformat("2026-08-19T14:30:45+02:00")
        title, stem = self.module.recording_identity("Kundemøde Q3", ["Zoom", "YouTube"], started)
        self.assertEqual(title, "Kundemøde Q3")
        self.assertEqual(stem, "2026-08-19-143045-kundemøde-q3")

        title, stem = self.module.recording_identity("", ["YouTube", "Zoom", "YouTube"], started)
        self.assertEqual(title, "YouTube + Zoom")
        self.assertEqual(stem, "2026-08-19-143045-youtube-zoom")

        title, stem = self.module.recording_identity("", [], started)
        self.assertEqual(title, "Transcript 2026-08-19 14:30")
        self.assertEqual(stem, "2026-08-19-143045-transcript")

    def test_installed_desktop_apps_are_exposed_as_picker_options(self):
        app_dir = Path(self.temp.name) / "applications"
        app_dir.mkdir()
        youtube = app_dir / "YouTube.desktop"
        youtube.write_text(
            "[Desktop Entry]\nType=Application\nName=YouTube\nExec=omarchy-launch-webapp https://youtube.com/\n",
            encoding="utf-8",
        )
        hidden = app_dir / "Hidden.desktop"
        hidden.write_text(
            "[Desktop Entry]\nType=Application\nName=Hidden\nNoDisplay=true\nExec=hidden\n",
            encoding="utf-8",
        )
        self.module.desktop_entry_paths = lambda: [youtube, hidden]
        apps = self.module.installed_apps()
        self.assertEqual([app["value"] for app in apps], ["YouTube"])
        self.assertIn("youtube", apps[0]["tokens"])
        self.assertEqual(apps[0]["description"], "youtube.com")

    def test_discord_can_be_excluded(self):
        self.module.installed_apps = lambda: [
            {"value": "Discord", "label": "Discord", "description": "discord.com", "tokens": ["discord"]}
        ]
        self.module.audio_clients = lambda kind: [{"haystack": "discord", "properties": {}, "kind": kind}]
        self.module.application_windows = lambda: ["discord voice channel"]
        config = self.module.default_config()
        config["sourceApps"] = []
        self.assertEqual(self.module.detect_source_app(config), "")
        config["sourceApps"] = ["Discord"]
        self.assertEqual(self.module.detect_source_app(config), "Discord")

    def test_youtube_window_with_playback_can_be_detected(self):
        self.module.installed_apps = lambda: [
            {"value": "YouTube", "label": "YouTube", "description": "youtube.com", "tokens": ["youtube"]}
        ]
        self.module.audio_clients = lambda kind: (
            [{"haystack": "zen browser audio", "properties": {}, "kind": kind}] if kind == "playback" else []
        )
        self.module.application_windows = lambda: ["video title - youtube — zen browser"]
        config = self.module.default_config()
        config["sourceApps"] = ["YouTube"]
        self.assertEqual(self.module.detect_source_app(config), "YouTube")

    def test_web_app_replaces_browser_but_keeps_other_audio_sources(self):
        self.module.installed_apps = lambda: [
            {"value": "Spotify", "label": "Spotify", "description": "spotify", "tokens": ["spotify"]},
            {"value": "YouTube", "label": "YouTube", "description": "youtube.com", "tokens": ["youtube"]},
            {"value": "zen", "label": "Zen Browser", "description": "zen", "tokens": ["zen browser", "zen"]},
        ]
        self.module.audio_clients = lambda kind: (
            [{"haystack": "zen browser playback", "properties": {}, "kind": kind},
             {"haystack": "spotify audio", "properties": {}, "kind": kind}]
            if kind == "playback" else []
        )
        self.module.application_windows = lambda: ["lecture - youtube — zen browser"]
        config = self.module.default_config()
        config["sourceApps"] = ["YouTube"]
        self.assertEqual(self.module.active_source_apps(config), ["Spotify", "YouTube"])


if __name__ == "__main__":
    unittest.main()
