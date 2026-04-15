from unittest.mock import MagicMock, patch

import pytest

from app.cli import (
    get_user_input,
    main,
    print_help,
    process_command,
)


class TestPrintFunctions:
    """Tests for CLI display/output functions."""

    def test_print_help(self, capsys: pytest.CaptureFixture) -> None:
        print_help()
        captured = capsys.readouterr().out
        assert "help" in captured
        assert "exit" in captured
        assert "history" in captured


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


class TestProcessCommand:
    """Tests for process_command()."""

    @pytest.mark.parametrize("cmd", ["exit", "quit", "q"])
    def test_exit_commands_return_true(self, cmd: str) -> None:
        assert process_command(cmd) is True

    def test_help_command(self, capsys: pytest.CaptureFixture) -> None:
        assert process_command("help") is False
        assert "Available Commands" in capsys.readouterr().out

    @patch("app.cli.chat", return_value="Bot reply")
    def test_chat_message(
        self, mock_chat: MagicMock, capsys: pytest.CaptureFixture
    ) -> None:
        assert process_command("What is data engineering?") is False
        mock_chat.assert_called_once_with("What is data engineering?")
        assert "Bot reply" in capsys.readouterr().out

    @patch("app.cli.chat", side_effect=Exception("Connection refused"))
    def test_chat_error_is_handled(
        self, mock_chat: MagicMock, capsys: pytest.CaptureFixture
    ) -> None:
        assert process_command("hello") is False
        captured = capsys.readouterr().out
        assert "Error" in captured
        assert "Connection refused" in captured


class TestMain:
    """Tests for the main() loop."""

    @patch("app.cli.get_user_input", side_effect=[None])
    @patch("app.cli.print_banner")
    def test_exits_on_none_input(
        self,
        mock_banner: MagicMock,
        mock_input: MagicMock,
        capsys: pytest.CaptureFixture,
    ) -> None:
        main()
        captured = capsys.readouterr().out
        assert "Exiting" in captured

    @patch("app.cli.get_user_input", side_effect=["exit"])
    @patch("app.cli.print_banner")
    def test_exits_on_exit_command(
        self,
        mock_banner: MagicMock,
        mock_input: MagicMock,
        capsys: pytest.CaptureFixture,
    ) -> None:
        main()
        captured = capsys.readouterr().out
        assert "Thank you" in captured

    @patch("app.cli.get_user_input", side_effect=["", "exit"])
    @patch("app.cli.print_banner")
    def test_skips_empty_input(
        self,
        mock_banner: MagicMock,
        mock_input: MagicMock,
        capsys: pytest.CaptureFixture,
    ) -> None:
        main()
        captured = capsys.readouterr().out
        assert "Thank you" in captured

    @patch("app.cli.get_user_input", side_effect=["help", "exit"])
    @patch("app.cli.print_banner")
    def test_processes_commands_then_exits(
        self,
        mock_banner: MagicMock,
        mock_input: MagicMock,
        capsys: pytest.CaptureFixture,
    ) -> None:
        main()
        captured = capsys.readouterr().out
        assert "Available Commands" in captured
        assert "Thank you" in captured

    @patch("app.cli.get_user_input", side_effect=KeyboardInterrupt)
    @patch("app.cli.print_banner")
    def test_handles_keyboard_interrupt(
        self, mock_banner: MagicMock, mock_input: MagicMock
    ) -> None:
        with pytest.raises(SystemExit) as exc_info:
            main()
        assert exc_info.value.code == 0
