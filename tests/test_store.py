import json
from unittest.mock import patch

import pytest

from app.store import (
    NO_DATA_PROMPT,
    CASContextManager,
    _load_context,
)


class TestLoadContext:
    """Tests for the _load_context helper."""

    def test_returns_dict_from_json_file(self, tmp_path):
        data = {"program": {"name": "Test"}}
        json_file = tmp_path / "context.json"
        json_file.write_text(json.dumps(data), encoding="utf-8")

        with patch("app.store.DATA_DIR", tmp_path):
            result = _load_context()

        assert result == data

    def test_returns_empty_dict_when_file_missing(self, tmp_path):
        with patch("app.store.DATA_DIR", tmp_path):
            result = _load_context()

        assert result == {}

    def test_preserves_utf8_characters(self, tmp_path):
        data = {"semester": "Frühlingssemester 2026"}
        json_file = tmp_path / "context.json"
        json_file.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")

        with patch("app.store.DATA_DIR", tmp_path):
            result = _load_context()

        assert result["semester"] == "Frühlingssemester 2026"

    def test_raises_on_invalid_json(self, tmp_path):
        json_file = tmp_path / "context.json"
        json_file.write_text("not valid json {{{", encoding="utf-8")

        with patch("app.store.DATA_DIR", tmp_path):
            with pytest.raises(json.JSONDecodeError):
                _load_context()


class TestCASContextManager:
    """Tests for CASContextManager."""

    def test_generates_system_prompt_with_context(self):
        context = {"program": {"name": "CAS Data Engineering"}}
        cfg = {"system_prompt": ""}

        CASContextManager(context, cfg)

        assert "COURSE_CONTEXT_START" in cfg["system_prompt"]
        assert "CAS Data Engineering" in cfg["system_prompt"]

    def test_uses_no_data_prompt_when_context_empty(self):
        cfg = {"system_prompt": ""}

        CASContextManager({}, cfg)

        assert cfg["system_prompt"] == NO_DATA_PROMPT

    def test_mutates_config_in_place(self):
        context = {"key": "value"}
        cfg = {"system_prompt": ""}
        original_id = id(cfg)

        CASContextManager(context, cfg)

        assert id(cfg) == original_id
        assert cfg["system_prompt"] != ""

    def test_system_prompt_contains_json_serialized_context(self):
        context = {"modules": ["Big Data", "Cloud"]}
        cfg = {"system_prompt": ""}

        CASContextManager(context, cfg)

        expected_block = json.dumps(context, ensure_ascii=False, indent=2)
        assert expected_block in cfg["system_prompt"]

    def test_system_prompt_follows_template_structure(self):
        context = {"test": True}
        cfg = {"system_prompt": ""}

        CASContextManager(context, cfg)

        prompt = cfg["system_prompt"]
        assert "You are a specialized chatbot" in prompt
        assert "COURSE_CONTEXT_START" in prompt

    def test_no_data_prompt_mentions_unavailable(self):
        assert (
            "not currently available" in NO_DATA_PROMPT
            or "No course data" in NO_DATA_PROMPT
        )
