# CAS-Bot

A chatbot that allows users to ask questions about the content and schedule of the CAS Data Engineering course.

## Table of Contents

- [Team](#team)
- [Installation](#installation)
- [Usage](#usage)
- [Branching Strategy](#branching-strategy-git-flow)
- [Architecture](#architecture)
- [API connection](#api-connection)
- [Store](#store)
- [CLI](#cli)

## Team

- Nicola
- Stephany
- Klaus

## Installation

### Requirements

1. Install uv:

In Linux/Mac
```
curl -LsSf https://astral.sh/uv/install.sh | sh

# OR via pip

pip install uv
```


2. Clone this repository and use `uv sync` from the `cas-bot` directory.   

Or download the .zip file and run 

```
unzip cas-bot.zip
cd cas-bot

# with uv
uv sync

# or with plain pip, but environment needs further configuration
pip install -e .
```


### Credentials

#### OpenAI

You need an API key from an OpenAI account with API credits (i.e., a billing plan). Go [here](https://platform.openai.com/settings/organization/api-keys) to learn how to generate your own key.  

Save the key in an .env file, e.g., in this repository save in the file `example.env`

```.env
OPENAI_API_KEY=your_api_key_here
```
#### API Key

To run the app, users must first authenticate. Save the API key (privately shared) in an .env file

```.env
API_KEY=your_api_key_here
```


## Usage

To execute the entire app, run:

In Linux/Mac:
```
chmod +x start.command #once
./start.command
```

In Windows:

Double-click `start.bat`, or run from the Command Prompt: `start.bat`


## Branching Strategy (Git Flow)

This project follows the **Git Flow** branching model:

![Branching Strategy](assets/Branching%20Strategy.png)

| Branch | Purpose |
|---|---|
| `main` | Production-ready code |
| `develop` | Integration branch for features |
| `feature/*` | New features, branched from `develop` |

### Merge Flow

1. Create a `feature/*` branch from `develop`
2. Work on the feature and open a merge request back into `develop`
4. When the code in develop is ready to release, open a merge request into `main`
5. If a critical bug is found in production, create a `hotfix/*` branch from `main` and merge the fix into both `main` and `develop`

## Architecture

The project has four components. Within [`app/`](app/):

1. `main.py`: The FastAPI app with four HTTP protocols.
2. `chat.py`: Sends the user's message plus conversation history to the LLM and returns the reply.
3. `store.py`: Has three elements
    - Config: holds the LLM settings (model, temperature, system prompt) in a dict that `chat.py` reads at runtime.
    - Context data: the course knowledge base.
    - CASContextManager: takes the context data and injects it into the system prompt.
4. `cli.py`: The Frontend of the app.

### API connection

The FastAPI app exposes four endpoints. All request and response bodies use JSON.

---

#### `POST /chat`

Send a message and receive a reply from the LLM.

**Request body**

| Field | Type | Description |
|---|---|---|
| `message` | `string` | The user's message |

**Response body**

| Field | Type | Description |
|---|---|---|
| `reply` | `string` | The LLM's response |

**Example**

```bash
curl -X POST http://localhost:8000/chat \
     -H "X-API-Key: [api-key]" \
     -H "Content-Type: application/json" \
     -d '{"message": "When does the Software Engineering module start?"}'
```

```json
{"reply": "The Software Engineering module starts on 2026-02-20."}
```

---

#### `GET /chat/history`

Retrieve the full conversation history for the current session.

**Response body**

| Field | Type | Description |
|---|---|---|
| `history` | `array` | List of messages with `role` and `content` |

**Example**

```bash
curl http://localhost:8000/chat/history \
     -H "X-API-Key: [api-key]"
```

```json
{
  "history": [
    {"role": "human", "content": "When does the Software Engineering module start?"},
    {"role": "ai", "content": "The Software Engineering module starts on 2026-02-20."}
  ]
}
```

---

#### `DELETE /chat/history`

Clear the full conversation history.

**Response body**

| Field | Type | Description |
|---|---|---|
| `message` | `string` | Confirmation message |

**Example**

```bash
curl -X DELETE http://localhost:8000/chat/history \
     -H "X-API-Key: [api-key]"
```

```json
{"message": "History cleared."}
```

---

#### `PUT /chat/history`

Not supported. Manual history updates are not allowed.

**Response body**

| Field | Type | Description |
|---|---|---|
| `message` | `string` | Explanation message |

**Example**

```bash
curl -X PUT http://localhost:8000/chat/history \
     -H "X-API-Key: [api-key]"
```

```json
{"message": "History cannot be manually updated."}
```

*Start the server first with `uv run uvicorn app.main:app --reload` to run examples.

### Store

#### Overview
The `store` module (`app/store.py`) serves as the central data management layer for the CAS-Bot. It is responsible for:

- Loading course context data from a JSON file
- Building and managing the system prompt sent to the LLM
- Holding the global LLM configuration (model, temperature, system prompt)
- Maintaining the conversation history

#### Context Loading

The `_load_context()` function reads the CAS Data Engineering course data from `data/context.json`. It returns an empty dict if the file is missing, allowing the bot to start gracefully even without data.


#### CASContextManager

The `CASContextManager` class takes the loaded context and the global `config` dict, then generates the system prompt by injecting the course data into a prompt template. If no context data is available, a fallback prompt is used instead.


#### Global Configuration

At module level, `store.py` initializes the shared `config` dict and `history` list that other modules import:


The `CASContextManager` mutates `config` in-place, so `config["system_prompt"]` is populated by the time any other module accesses it.

#### Usage in chat.py

The `chat` module imports `config` and `history` from the store and uses them to configure the LLM and manage conversation state:

Because `config` and `history` are mutable objects shared by reference, any updates made through the `CASContextManager` are immediately visible to `chat.py`.

### CLI

#### Overview
The `cli` module (`app/cli.py`) is the terminal-based frontend for CAS-Bot. It provides an interactive chat interface that communicates with the FastAPI backend over HTTP.

#### Available Commands

| Command | Description |
|---|---|
| `help` | Show available commands and troubleshooting info |
| `clear` / `reset` | Clear the conversation history |
| `history` | Show the conversation history |
| `info` | Show course information (name, semester, institution) |
| `exit` / `quit` / `q` | Exit the chatbot |

Any other input is sent as a chat message to the backend.

#### How It Works

The `main()` function runs the interactive loop:

1. `print_banner()` displays a welcome message with course details.
2. `get_user_input()` reads a line from the terminal.
3. `process_command()` checks whether the input matches a built-in command.

#### Configuration

The CLI reads two environment variables from `.env`:

| Variable | Purpose |
|---|---|
| `API_KEY` | Passed in the `X-API-Key` header for backend authentication |

The backend URL defaults to `http://localhost:8000`.
