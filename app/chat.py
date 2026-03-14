# Logic handling interaction with the llm
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI

from app.store import config, history


def chat(user_message: str) -> str:
    llm = ChatOpenAI(
        model=config["model"],
        temperature=config["temperature"],
    )

    history.append(HumanMessage(content=user_message))

    messages = [SystemMessage(content=config["system_prompt"])] + history
    response = llm.invoke(messages)

    history.append(response)

    return str(response.content)
