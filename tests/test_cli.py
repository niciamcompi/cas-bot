from unittest.mock import MagicMock, patch

import pytest

from app.cli import (
    chat,
    clear_history,
    get_user_input,
    main,
    print_banner,
    print_course_info,
    print_help,
    print_history,
    process_command,
)

# Fixtures
@pytest.fixture()
def mock_context():
    """Provide a minimal cas_data_engineering_context for tests."""
    return {
        "program": {
            "name": "CAS Data Engineering",
            "semester": "FS2025",
            "institution": "FHNW",
            "teaching_time": "Fridays 09-17",
        }
    }



# chat()
class TestChat:
    """Tests for the chat() API wrapper."""

    @patch("app.cli.requests.post")
    def test_chat_returns_reply(self, mock_post: MagicMock) -> None:
        mock_post.return_value.json.return_value = {"reply": "Hello!"}
        mock_post.return_value.raise_for_status = MagicMock()

        result = chat("Hi")

        mock_post.assert_called_once_with(
            "http://localhost:8000/chat", json={"message": "Hi"}
        )
        assert result == "Hello!"

    @patch("app.cli.requests.post")
    def test_chat_raises_on_http_error(self, mock_post: MagicMock) -> None:
        mock_post.return_value.raise_for_status.side_effect = Exception("500 Server Error")

        with pytest.raises(Exception, match="500 Server Error"):
            chat("Hi")


# Output functions (print_banner, print_help, print_course_info)
class TestPrintFunctions:
    """Tests for CLI display/output functions."""

    @patch("app.cli.cas_data_engineering_context")
    def test_print_banner(self, mock_ctx: MagicMock, mock_context: dict, capsys: pytest.CaptureFixture) -> None:
        mock_ctx.__getitem__ = mock_context.__getitem__
        print_banner()
        captured = capsys.readouterr().out
        assert "CAS Data Engineering Chatbot" in captured

    def test_print_help(self, capsys: pytest.CaptureFixture) -> None:
        print_help()
        captured = capsys.readouterr().out
        assert "help" in captured
        assert "exit" in captured
        assert "history" in captured

    @patch("app.cli.cas_data_engineering_context")
    def test_print_course_info(self, mock_ctx: MagicMock, mock_context: dict, capsys: pytest.CaptureFixture) -> None:
        mock_ctx.__getitem__ = mock_context.__getitem__
        print_course_info()
        captured = capsys.readouterr().out
        assert "Course Information" in captured


# print_history()
class TestPrintHistory:
    """Tests for print_history()."""

    @patch("app.cli.requests.get")
    def test_empty_history(self, mock_get: MagicMock, capsys: pytest.CaptureFixture) -> None:
        mock_get.return_value.json.return_value = {"history": []}

        print_history()

        captured = capsys.readouterr().out
        assert "No conversation history yet" in captured

    @patch("app.cli.requests.get")
    def test_history_with_messages(self, mock_get: MagicMock, capsys: pytest.CaptureFixture) -> None:
        mock_get.return_value.json.return_value = {
            "history": [
                {"role": "human", "content": "Hello"},
                {"role": "assistant", "content": "Hi there!"},
            ]
        }

        print_history()

        captured = capsys.readouterr().out
        assert "2 messages" in captured
        assert "User" in captured
        assert "Assistant" in captured

    @patch("app.cli.requests.get")
    def test_history_truncates_long_messages(self, mock_get: MagicMock, capsys: pytest.CaptureFixture) -> None:
        mock_get.return_value.json.return_value = {
            "history": [{"role": "human", "content": "A" * 150}]
        }

        print_history()

        captured = capsys.readouterr().out
        assert "..." in captured



# clear_history()
class TestClearHistory:
    """Tests for clear_history()."""

    @patch("app.cli.requests.delete")
    def test_clear_history(self, mock_delete: MagicMock, capsys: pytest.CaptureFixture) -> None:
        clear_history()

        mock_delete.assert_called_once_with("http://localhost:8000/chat/history")
        captured = capsys.readouterr().out
        assert "cleared" in captured



# get_user_input()
class TestGetUserInput:
    """Tests for get_user_input()."""

    @patch("builtins.input", return_value="  hello  ")
    def test_returns_stripped_input(self, mock_input: MagicMock) -> None:
        assert get_user_input() == "hello"

    @patch("builtins.input", side_effect=EOFError)
    def test_returns_none_on_eof(self, mock_input: MagicMock) -> None:
        assert get_user_input() is None

    @patch("builtins.input", side_effect=KeyboardInterrupt)
    def test_returns_none_on_interrupt(self, mock_input: MagicMock) -> None:
        assert get_user_input() is None


# process_command()
class TestProcessCommand:
    """Tests for process_command()."""

    @pytest.mark.parametrize("cmd", ["exit", "quit", "q"])
    def test_exit_commands_return_true(self, cmd: str) -> None:
        assert process_command(cmd) is True

    def test_help_command(self, capsys: pytest.CaptureFixture) -> None:
        assert process_command("help") is False
        assert "Available Commands" in capsys.readouterr().out

    @patch("app.cli.requests.delete")
    def test_clear_command(self, mock_delete: MagicMock, capsys: pytest.CaptureFixture) -> None:
        assert process_command("clear") is False
        assert "cleared" in capsys.readouterr().out

    @patch("app.cli.requests.delete")
    def test_reset_command(self, mock_delete: MagicMock, capsys: pytest.CaptureFixture) -> None:
        assert process_command("reset") is False

    @patch("app.cli.requests.get")
    def test_history_command(self, mock_get: MagicMock, capsys: pytest.CaptureFixture) -> None:
        mock_get.return_value.json.return_value = {"history": []}
        assert process_command("history") is False

    @patch("app.cli.cas_data_engineering_context")
    def test_info_command(self, mock_ctx: MagicMock, mock_context: dict, capsys: pytest.CaptureFixture) -> None:
        mock_ctx.__getitem__ = mock_context.__getitem__
        assert process_command("info") is False
        assert "Course Information" in capsys.readouterr().out

    @patch("app.cli.chat", return_value="Bot reply")
    def test_chat_message(self, mock_chat: MagicMock, capsys: pytest.CaptureFixture) -> None:
        assert process_command("What is data engineering?") is False
        mock_chat.assert_called_once_with("What is data engineering?")
        assert "Bot reply" in capsys.readouterr().out

    @patch("app.cli.chat", side_effect=Exception("Connection refused"))
    def test_chat_error_is_handled(self, mock_chat: MagicMock, capsys: pytest.CaptureFixture) -> None:
        assert process_command("hello") is False
        captured = capsys.readouterr().out
        assert "Error" in captured
        assert "Connection refused" in captured


# main()
class TestMain:
    """Tests for the main() loop."""

    @patch("app.cli.get_user_input", side_effect=[None])
    @patch("app.cli.print_banner")
    def test_exits_on_none_input(self, mock_banner: MagicMock, mock_input: MagicMock, capsys: pytest.CaptureFixture) -> None:
        main()
        captured = capsys.readouterr().out
        assert "Exiting" in captured

    @patch("app.cli.get_user_input", side_effect=["exit"])
    @patch("app.cli.print_banner")
    def test_exits_on_exit_command(self, mock_banner: MagicMock, mock_input: MagicMock, capsys: pytest.CaptureFixture) -> None:
        main()
        captured = capsys.readouterr().out
        assert "Thank you" in captured

    @patch("app.cli.get_user_input", side_effect=["", "exit"])
    @patch("app.cli.print_banner")
    def test_skips_empty_input(self, mock_banner: MagicMock, mock_input: MagicMock, capsys: pytest.CaptureFixture) -> None:
        main()
        captured = capsys.readouterr().out
        assert "Thank you" in captured

    @patch("app.cli.get_user_input", side_effect=["help", "exit"])
    @patch("app.cli.print_banner")
    def test_processes_commands_then_exits(self, mock_banner: MagicMock, mock_input: MagicMock, capsys: pytest.CaptureFixture) -> None:
        main()
        captured = capsys.readouterr().out
        assert "Available Commands" in captured
        assert "Thank you" in captured

    @patch("app.cli.get_user_input", side_effect=KeyboardInterrupt)
    @patch("app.cli.print_banner")
    def test_handles_keyboard_interrupt(self, mock_banner: MagicMock, mock_input: MagicMock) -> None:
        with pytest.raises(SystemExit) as exc_info:
            main()
        assert exc_info.value.code == 0
