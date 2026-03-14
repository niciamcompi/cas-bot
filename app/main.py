from fastapi import FastAPI
from pydantic import BaseModel

from app.chat import chat

app = FastAPI()


class ChatRequest(BaseModel):
    message: str


class ChatResponse(BaseModel):
    reply: str


@app.post("/chat", response_model=ChatResponse)
def chat_endpoint(request: ChatRequest) -> ChatResponse:
    reply = chat(request.message)
    return ChatResponse(reply=reply)
