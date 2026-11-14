# syntax=docker/dockerfile:1
# Multi-Stage-Build:
#   1. "base":    Python-Umgebung mit allen Abhängigkeiten (aus uv.lock, exakt gepinnt)
#   2. "train":   lädt die BAG-Daten, prüft sie und trainiert das Modell
#   3. "runtime": schlankes Image nur mit Code, Modell und aufbereiteten Daten, non-root
# Ergebnis: Ein Image = eine exakt reproduzierbare Modellversion.
#
# Firmenumgebung (interne Registry, TLS-Proxy mit eigenem Zertifikat):
#   docker build \
#     --build-arg PYTHON_IMAGE=registry.firma.ch/python:3.12-slim \
#     --secret id=ca_bundle,src=/pfad/zu/firmen-ca.pem \
#     -t marktradar .
# Das Zertifikat wird nur während des Builds eingebunden und landet nicht im Image.

ARG PYTHON_IMAGE=python:3.12-slim

FROM ${PYTHON_IMAGE} AS base
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy PYTHONUNBUFFERED=1
WORKDIR /app
# Hilfsskript: setzt das optionale Firmen-CA-Zertifikat für pip, uv und httpx
RUN printf '#!/bin/sh\nif [ -f /run/secrets/ca_bundle ]; then export SSL_CERT_FILE=/run/secrets/ca_bundle PIP_CERT=/run/secrets/ca_bundle; fi\nexec "$@"\n' \
      > /usr/local/bin/with-ca && chmod +x /usr/local/bin/with-ca
RUN --mount=type=secret,id=ca_bundle,required=false \
    with-ca pip install --no-cache-dir uv==0.11.32
# Erst nur die Abhängigkeiten -> Docker-Cache bleibt gültig, solange uv.lock gleich bleibt
COPY pyproject.toml uv.lock README.md ./
RUN --mount=type=secret,id=ca_bundle,required=false \
    with-ca uv sync --frozen --no-dev --no-install-project
COPY src ./src
COPY config ./config
RUN --mount=type=secret,id=ca_bundle,required=false \
    with-ca uv sync --frozen --no-dev

FROM base AS train
RUN --mount=type=secret,id=ca_bundle,required=false \
    with-ca uv run --no-sync marktradar download \
 && uv run --no-sync marktradar build \
 && uv run --no-sync marktradar train

FROM ${PYTHON_IMAGE} AS runtime
WORKDIR /app
RUN useradd --create-home --uid 10001 app
COPY --from=base /app /app
COPY --from=train /app/models ./models
COPY --from=train /app/data/processed ./data/processed
ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1
USER app
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"
CMD ["marktradar", "serve", "--host", "0.0.0.0", "--port", "8000"]
