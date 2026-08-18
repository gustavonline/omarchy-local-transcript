#!/usr/bin/env python3

import importlib.machinery
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_backend():
    loader = importlib.machinery.SourceFileLoader("local_meeting", str(ROOT / "local-meeting"))
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
        self.module.CONFIG_PATH = self.module.CONFIG_DIR / "local-meeting.json"
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

    def test_markdown_document_is_portable(self):
        session = Path(self.temp.name) / "meeting"
        session.mkdir()
        (session / "transcript.json").write_text("{}\n", encoding="utf-8")
        active = {
            "title": "Dansk statusmøde",
            "started_at": "2026-08-18T14:30:00+02:00",
            "session_dir": str(session),
        }
        self.module.atomic_json(self.module.CONFIG_PATH, {
            **self.module.default_config(),
            "sttModel": "small",
            "summaryModel": "qwen3.5:2b",
        })
        (session / "manual-notes.jsonl").write_text(
            json.dumps({"timestamp": "2026-08-18T14:31:00+02:00", "author": "Gustav", "note": "Send planen"}) + "\n",
            encoding="utf-8",
        )
        output = self.module.finish_document(
            active,
            "## Summary\n\nKort dansk resumé.",
            "# Dansk statusmøde\n\n## Transcript\n\n*[00:01]* Hej.\n",
            {},
        )
        text = output.read_text(encoding="utf-8")
        self.assertIn("tags: [meeting]", text)
        self.assertIn("## Manual notes", text)
        self.assertIn("- **14:31 — Gustav:** Send planen", text)
        self.assertIn("[Structured transcript](transcript.json)", text)
        self.assertEqual(text.count("# Dansk statusmøde"), 1)

    def test_discord_can_be_excluded(self):
        self.module.microphone_clients = lambda: [{"haystack": "discord discordcanary", "properties": {}}]
        self.module.meeting_windows = lambda: "discord voice channel"
        config = self.module.default_config()
        config["detectionApps"] = [item for item in config["detectionApps"] if item != "discord"]
        self.assertEqual(self.module.detect_meeting_app(config), "")
        config["detectionApps"].append("discord")
        self.assertEqual(self.module.detect_meeting_app(config), "Discord")

    def test_custom_microphone_app_can_be_added(self):
        self.module.microphone_clients = lambda: [{"haystack": "application.name mycompanycall", "properties": {}}]
        self.module.meeting_windows = lambda: ""
        config = self.module.default_config()
        config["detectionApps"] = []
        config["customMeetingApps"] = "mycompanycall"
        self.assertEqual(self.module.detect_meeting_app(config), "mycompanycall")


if __name__ == "__main__":
    unittest.main()
