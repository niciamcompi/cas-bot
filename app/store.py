import json
from pathlib import Path
from typing import Any, Dict, List

from langchain_core.messages import BaseMessage

history: List[BaseMessage] = []

DATA_DIR = Path(__file__).parent / "data"


def _load_context() -> Dict[str, Any]:
    """Load the CAS Data Engineering context from a JSON file.

    Returns an empty dict if the file is missing.
    """
    path = DATA_DIR / "context.json"
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


class CASContextManager:
    """CRUD manager for the CAS Data Engineering context data.

    Mutates the config dict in-place so that existing references (e.g. in
    chat.py) stay valid.
    """

    def __init__(self, context: Dict[str, Any], config: Dict[str, Any]) -> None:
        self._context = context
        self._config = config
        self._regenerate()

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _regenerate(self) -> None:
        if not self._context:
            self._config["system_prompt"] = NO_DATA_PROMPT
            return
        context_block = json.dumps(self._context, ensure_ascii=False, indent=2)
        self._config["system_prompt"] = SYSTEM_PROMPT_TEMPLATE.format(
            context_block=context_block
        )


NO_DATA_PROMPT = (
    "No course data is currently available. "
    "If a user asks a question, politely inform them that the CAS Data Engineering "
    "course data could not be loaded and suggest they try again later or contact support."
)

SYSTEM_PROMPT_TEMPLATE = """
You are a specialized chatbot for the CAS Data Engineering course.

Your role:
- Answer only questions that are directly related to the CAS Data Engineering course.
- Use only the course content provided in the conversation context as your source of truth.
- Treat the provided context as the authoritative material for answering questions.

Behavior rules:
- Only answer questions that are relevant to the CAS Data Engineering course, such as questions about course modules, topics, structure, requirements, schedules, learning goals, assignments, exams, or other course-related information contained in the provided context.
- Do not answer unrelated questions, even if you know the answer.
- If a question is outside the scope of the CAS Data Engineering course, politely refuse and explain that you can only help with questions related to this course.
- If the answer is not contained in the provided context, say clearly that the information is not available in the provided course material.
- Do not invent, assume, or hallucinate missing details.
- Keep answers clear, accurate, and concise.
- When helpful, reference or summarize the relevant part of the provided context.
- If the user's question is ambiguous, interpret it in the most course-relevant way possible based on the provided context.

Examples of valid responses:
- "Based on the provided course material, the CAS Data Engineering program includes …"
- "I can only help with questions related to the CAS Data Engineering course."
- "This information is not available in the course content provided to me."

Important constraint:
- Your knowledge must be limited to the CAS Data Engineering course content passed in the context. Do not rely on external knowledge unless it is explicitly included in the provided context.

COURSE_CONTEXT_START
{context_block}
    """

cas_data_engineering_context = _load_context()

config: dict = {
    "system_prompt": "",
    "temperature": 0.7,
    "model": "gpt-5-mini",
}

context_manager = CASContextManager(cas_data_engineering_context, config)
