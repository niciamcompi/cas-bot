from dotenv import load_dotenv
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI

from app.store import config, history

load_dotenv()


def chat(user_message: str) -> str:
    llm = ChatOpenAI(
        model=config["model"],
        temperature=config["temperature"],
    )

    history.append(HumanMessage(content=user_message))

    messages = [SystemMessage(content=config["system_prompt"])] + history
    response = llm.invoke(messages)

    history.append(response)
    del history[:-10]

    return str(response.content)
