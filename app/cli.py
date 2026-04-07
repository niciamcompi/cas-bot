import sys
from typing import Optional

from app.chat import chat
from app.store import cas_data_engineering_context, history


class Colors:
    """ANSI color codes for terminal output."""

    BLUE = "\033[94m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    RESET = "\033[0m"
    BOLD = "\033[1m"


def print_banner():
    """Print welcome banner."""
    print(f"{Colors.BOLD}{Colors.BLUE}")
    print("=" * 70)
    print("CAS Data Engineering Chatbot")
    print("=" * 70)
    print(f"{Colors.RESET}")
    print(f"{Colors.GREEN}Course: {cas_data_engineering_context['program']['name']}")
    print(f"Semester: {cas_data_engineering_context['program']['semester']}")
    print(
        f"Institution: {cas_data_engineering_context['program']['institution']}{Colors.RESET}"
    )
    print()
    print(
        f"{Colors.YELLOW}Type 'help' for available commands or 'exit' to quit{Colors.RESET}"
    )
    print("-" * 70)
    print()


def print_help():
    """Print available commands."""
    print(f"\n{Colors.BOLD}Available Commands:{Colors.RESET}")
    print(f"  {Colors.GREEN}help{Colors.RESET}          - Show this help message")
    print(f"  {Colors.GREEN}clear/reset{Colors.RESET}   - Clear conversation history")
    print(f"  {Colors.GREEN}history{Colors.RESET}       - Show conversation history")
    print(f"  {Colors.GREEN}info{Colors.RESET}          - Show course information")
    print(f"  {Colors.GREEN}exit/quit{Colors.RESET}     - Exit the chatbot")
    print()


def print_history():
    """Print conversation history."""
    if not history:
        print(f"{Colors.YELLOW}No conversation history yet.{Colors.RESET}\n")
        return

    print(
        f"\n{Colors.BOLD}Conversation History ({len(history)} messages):{Colors.RESET}"
    )
    for i, msg in enumerate(history, 1):
        role = "User" if msg.__class__.__name__ == "HumanMessage" else "Assistant"
        color = Colors.BLUE if role == "User" else Colors.GREEN
        content_preview = (
            str(msg.content)[:100] + "..."
            if len(str(msg.content)) > 100
            else str(msg.content)
        )
        print(f"{color}{i}. {role}:{Colors.RESET} {content_preview}")
    print()


def clear_history():
    """Clear conversation history."""
    history.clear()
    print(f"{Colors.GREEN}✓ Conversation history cleared.{Colors.RESET}\n")


def print_course_info():
    """Print course information."""
    prog = cas_data_engineering_context["program"]
    print(f"\n{Colors.BOLD}Course Information:{Colors.RESET}")
    print(f"  Name: {prog['name']}")
    print(f"  Semester: {prog['semester']}")
    print(f"  Teaching Time: {prog['teaching_time']}")
    print(f"  Institution: {prog['institution']}")
    print()


def get_user_input() -> Optional[str]:
    """
    Get user input with proper prompt.

    Returns:
        User input string or None if EOF/interrupt
    """
    try:
        return input(f"{Colors.BLUE}You:{Colors.RESET} ").strip()
    except (EOFError, KeyboardInterrupt):
        return None


def process_command(user_input: str) -> bool:
    """
    Process special commands.

    Args:
        user_input: User's input string

    Returns:
        True if should exit, False otherwise
    """
    command = user_input.lower()

    if command in ["exit", "quit", "q"]:
        return True

    elif command == "help":
        print_help()

    elif command in ["clear", "reset"]:
        clear_history()

    elif command == "history":
        print_history()

    elif command == "info":
        print_course_info()

    else:
        # Not a command, process as chat message
        try:
            response = chat(user_input)
            print(f"{Colors.GREEN}Assistant:{Colors.RESET} {response}\n")
        except Exception as e:
            print(f"{Colors.RED}Error: {e}{Colors.RESET}\n")
            print(
                f"{Colors.YELLOW}Please try again or type 'help' for available commands.{Colors.RESET}\n"
            )

    return False


def main():
    """Main CLI loop."""
    print_banner()

    try:
        while True:
            user_input = get_user_input()

            # Handle EOF or interrupt
            if user_input is None:
                print(f"\n{Colors.YELLOW}Exiting chatbot...{Colors.RESET}")
                break

            # Skip empty input
            if not user_input:
                continue

            # Process command or chat message
            should_exit = process_command(user_input)
            if should_exit:
                print(
                    f"{Colors.YELLOW}Thank you for using the CAS Data Engineering Chatbot!{Colors.RESET}"
                )
                break

    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Interrupted. Exiting chatbot...{Colors.RESET}")
        sys.exit(0)
    except Exception as e:
        print(f"\n{Colors.RED}Fatal error: {e}{Colors.RESET}")
        sys.exit(1)


if __name__ == "__main__":
    main()
