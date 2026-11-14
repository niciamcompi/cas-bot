.PHONY: install lint test pipeline serve docker

install:          ## Abhängigkeiten installieren
	uv sync

lint:             ## Formatierung, Linting, Typprüfung
	uv run ruff format --check .
	uv run ruff check .
	uv run mypy src

test:             ## Tests mit Coverage
	uv run pytest

pipeline:         ## Komplette ML-Pipeline auf echten BAG-Daten
	uv run marktradar download
	uv run marktradar build
	uv run marktradar train

serve:            ## API lokal starten (http://localhost:8000/docs)
	uv run marktradar serve

docker:           ## Image bauen (trainiert im Build) und starten
	docker build -t marktradar .
	docker run --rm -p 8000:8000 marktradar
