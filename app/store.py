import json
from typing import Any, Dict, List

from langchain_core.messages import BaseMessage

history: List[BaseMessage] = []


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
        context_block = json.dumps(self._context, ensure_ascii=False, indent=2)
        self._config["system_prompt"] = SYSTEM_PROMPT_TEMPLATE.format(
            context_block=context_block
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

cas_data_engineering_context = {
    "program": {
        "name": "CAS Data Engineering",
        "semester": "Frühlingssemester 2026",
        "teaching_time": "08:45-16:30",
        "institution": "FHNW Hochschule für Informatik",
    },
    "schedule": {
        "source_note": "'Terminplan CAS Data Engineering Frühlingssemester 2026'.",
        "legend": {
            "yellow": "Schulferien Windisch",
            "orange_cells": "Weekend/holiday markers in calendar",
        },
        "holidays": [
            {"date": "2026-05-01", "name": "1. Mai"},
            {"date": "2026-04-03", "name": "Karfreitag"},
            {"date": "2026-04-05", "name": "Ostern"},
            {"date": "2026-04-06", "name": "Ostermontag"},
            {"date": "2026-05-14", "name": "Auffahrt"},
            {"date": "2026-05-25", "name": "Pfingstmontag"},
        ],
        "events": [
            {
                "module": "Software-Engineering",
                "dates": ["2026-02-20", "2026-02-21", "2026-02-22"],
                "room": "Raum 6.1D57",
                "certainty": "medium",
            },
            {
                "module": "Software-Engineering",
                "dates": ["2026-02-28"],
                "room": "Raum 6.1D57",
                "certainty": "high",
            },
            {
                "module": "Software-Engineering / Containerisierung",
                "dates": ["2026-03-06", "2026-03-07", "2026-03-08"],
                "room": "Raum 6.1D51",
                "certainty": "medium",
            },
            {
                "module": "Containerisierung",
                "dates": ["2026-03-13", "2026-03-14", "2026-03-15"],
                "room": "Raum 6.1D57 / Raum 6.1D51",
                "certainty": "low",
            },
            {
                "module": "Datenbanken & DWH",
                "dates": ["2026-03-20", "2026-03-21", "2026-03-22"],
                "room": "Raum 5.1C56",
                "certainty": "medium",
            },
            {
                "module": "Datenbanken & DWH",
                "dates": ["2026-03-27", "2026-03-28", "2026-03-29"],
                "room": "Raum 5.1C56",
                "certainty": "medium",
            },
            {
                "module": "Data Wrangling",
                "dates": ["2026-04-24", "2026-04-25", "2026-04-26"],
                "room": "Raum 6.1D51 / Raum 5.1C59",
                "certainty": "medium",
            },
            {
                "module": "Big Data",
                "dates": ["2026-05-02", "2026-05-03"],
                "room": "Raum 5.1C56",
                "certainty": "medium",
            },
            {
                "module": "Big Data",
                "dates": ["2026-05-08", "2026-05-09", "2026-05-10"],
                "room": "Raum 5.1C54",
                "certainty": "medium",
            },
            {
                "module": "Reserve",
                "dates": ["2026-05-22"],
                "room": None,
                "certainty": "high",
            },
            {
                "module": "Cloud",
                "dates": ["2026-05-30", "2026-05-31"],
                "room": "Raum 6.1D51",
                "certainty": "medium",
            },
            {
                "module": "Databricks / Cloud",
                "dates": ["2026-06-05", "2026-06-06", "2026-06-07"],
                "room": "Raum 6.1D51",
                "certainty": "medium",
            },
            {
                "module": "Data Science / Architektur",
                "dates": ["2026-06-12", "2026-06-13", "2026-06-14"],
                "room": "Raum 6.1D51",
                "certainty": "medium",
            },
            {
                "module": "ML in Production",
                "dates": ["2026-06-19"],
                "room": "Raum 6.1D51",
                "certainty": "medium",
            },
            {
                "module": "Reserve",
                "dates": ["2026-06-20", "2026-06-21"],
                "room": None,
                "certainty": "medium",
            },
            {
                "module": "ML in Production / Abschluss",
                "dates": ["2026-06-26", "2026-06-27", "2026-06-28"],
                "room": "Raum 6.0D13 / Raum 5.1C56 / Raum 5.1C59",
                "certainty": "low",
            },
        ],
    },
    "assessment_overview": {
        "source_note": "Extracted from screenshot of spreadsheet 'Leistungsbeurteilung'.",
        "columns": [
            "Modul",
            "Prüfung",
            "Vorgezogener Prüfungstermin",
            "Projektarbeit Testat",
            "Projektarbeit Note",
            "Projekt Gruppengrösse",
            "Prüfungsmodalitäten",
        ],
        "rows": [
            {
                "module": "Software-Engineering",
                "exam": None,
                "early_exam_date": None,
                "project_work_testat": None,
                "project_work_grade_due": "2026-04-23 23:59:59",
                "project_group_size": 2,
                "exam_modalities": "Projekt wird abgegeben und im Anschluss mündlich (online) besprochen.",
            },
            {
                "module": "Containerisierung",
                "exam": "2026-06-27",
                "early_exam_date": "2026-03-28",
                "project_work_testat": None,
                "project_work_grade_due": None,
                "project_group_size": None,
                "exam_modalities": "ohne Unterlagen",
            },
            {
                "module": "Datenbanken & DWH",
                "exam": "individuell",
                "early_exam_date": "Link zur Online-Prüfung",
                "project_work_testat": None,
                "project_work_grade_due": None,
                "project_group_size": None,
                "exam_modalities": "mit Unterlagen",
            },
            {
                "module": "Data Wrangling",
                "exam": None,
                "early_exam_date": None,
                "project_work_testat": "2026-05-22",
                "project_work_grade_due": None,
                "project_group_size": "1-2",
                "exam_modalities": None,
            },
            {
                "module": "Big Data",
                "exam": None,
                "early_exam_date": None,
                "project_work_testat": None,
                "project_work_grade_due": "2026-06-04",
                "project_group_size": "1 oder 2",
                "exam_modalities": None,
            },
            {
                "module": "Cloud Grundlagen",
                "exam": None,
                "early_exam_date": None,
                "project_work_testat": "2026-06-27 08:30",
                "project_work_grade_due": None,
                "project_group_size": None,
                "exam_modalities": None,
            },
            {
                "module": "Data Science",
                "exam": "2026-06-27",
                "early_exam_date": None,
                "project_work_testat": None,
                "project_work_grade_due": None,
                "project_group_size": None,
                "exam_modalities": "1 A4-Seite",
            },
            {
                "module": "ML in Production",
                "exam": "-",
                "early_exam_date": None,
                "project_work_testat": None,
                "project_work_grade_due": None,
                "project_group_size": None,
                "exam_modalities": None,
            },
            {
                "module": "Architektur",
                "exam": None,
                "early_exam_date": None,
                "project_work_testat": "2026-06-27 08:30",
                "project_work_grade_due": None,
                "project_group_size": None,
                "exam_modalities": None,
            },
            {
                "module": "Eigener Use-Case",
                "exam": None,
                "early_exam_date": None,
                "project_work_testat": "2026-06-27",
                "project_work_grade_due": None,
                "project_group_size": None,
                "exam_modalities": None,
            },
        ],
        "rules": [
            "Eine Projektarbeit muss nicht erarbeitet werden.",
            "Bitte Dozierende beim Auslassen informieren (braucht keine Begründung).",
            "Alle abgegebenen Projektarbeiten werden benotet und tragen zur Gesamtnote bei.",
            "Der Use-Case am Ende muss präsentiert werden.",
            "Die CAS Data Engineering Note berechnet sich aus dem Mittelwert der Prüfungen und aller benoteten Projektarbeiten.",
        ],
    },
    "use_case_presentation_guidelines": {
        "title": "Vorgabe an die Use-Case Präsentation",
        "subtitle": "CAS Data Engineering",
        "general_requirements": {
            "max_slides": 10,
            "duration_minutes": 10,
            "description": (
                "Für die Abschlussveranstaltung ist eine Präsentation (max. 10 Slides) "
                "mit einem Umfang von 10 Minuten zu erstellen."
            ),
            "allowed_topic": (
                "Die Präsentation kann den Eingangs-Use-Case aufgreifen oder einen Use-Case, "
                "den man in der Zwischenzeit als echtes Problem identifiziert hat."
            ),
            "expectation": (
                "In der Präsentation soll eine Lösungsidee gezeigt werden, die ein oder mehrere "
                "behandelte Module aufgreift und verteidigt. Es wird 1-2 Rückfragen geben."
            ),
            "reuse_of_existing_work": (
                "Bereits erstellte Lösungen aus anderen Modulen dürfen verwendet und in "
                "eine kurze, prägnante Slide-Form überführt werden."
            ),
            "important_note": "Es muss nichts umgesetzt werden.",
            "pitch_goal": (
                "Die Präsentation soll so gestaltet sein, dass man sie theoretisch an den "
                "Arbeitsplatz mitnehmen und die Idee bzw. Lösung dort pitchen könnte."
            ),
        },
        "slide_outline": [
            "Warum jetzt? Was hat sich bei Ihnen intern oder in der Welt verändert, sodass dies jetzt der richtige Zeitpunkt ist für Ihre Idee?",
            "Was würde passieren, wenn Sie nichts tun? (Was ist der aktuelle 'Pain', was erwarten Sie durch die Verbesserung? 'Win')",
            "Was ist das Problem, welches Sie lösen möchten?",
            "Wie sieht ihr Fix / Ihre Lösung aus?",
            "Welche Schritte haben Sie bereits unternommen? Gibt es bereits einen POC, Code, ein Dokument oder etwas in grafischer Form?",
            "Call-to-Action: Was wünschen Sie sich als nächsten Schritt? (Projektzeit, um die Sache voranzubringen? Ressourcen? Teammitglieder?)",
        ],
        "example_use_case": {
            "context_note": (
                "Das Beispiel ist stark vereinfacht und ohne grafische Darstellungen. "
                "Für die echte Präsentation sollen mehr Details, Grafiken oder Architekturvorschläge "
                "gezeigt und Technologien begründet werden."
            ),
            "initial_situation": (
                "Verschiedene Maschinen-Sensoren speichern dezentral Messwerte in einfache Text-Dateien. "
                "Einmal pro Woche werden diese manuell in eine neue Excel-Datei zusammengeführt, "
                "danach werden Visualisierungen in Excel erstellt und den Maschinen-Ingenieuren per E-Mail zugeschickt."
            ),
            "why_now": (
                "Zu Beginn waren es lediglich 2 Maschinen. Nun sind es bereits 6 und es werden ständig mehr. "
                "Geplant ist, dass in einem Jahr 20 Maschinen desselben Typs täglich laufen und Daten produzieren."
            ),
            "if_nothing_changes": (
                "Der manuelle Aufwand für das Zusammentragen wird immer grösser und aufgrund der verteilten Daten "
                "auch fehleranfälliger. Es gehen immer wieder Dateien vergessen. Zudem wünschen sich die "
                "Maschinen-Ingenieure, dass sie aktuelle Daten einsehen können anstelle der Daten der vergangenen Woche."
            ),
            "problem_to_solve": [
                "Weniger Fehlerpotenzial und weniger manueller Aufwand beim Zusammentragen der Daten.",
                "Keine manuelle Verteilung der Auswertungen.",
                "Keine wochenalten Daten, sondern nahezu Live-Datenvisualisierungen für Maschinen-Ingenieure.",
                "Skalierbarkeit für die Zukunft.",
                "Lösung, die auch bei Kundinnen und Kunden eingesetzt werden kann.",
            ],
            "proposed_solution": (
                "Eine Applikation läuft ständig und überwacht alle Ordner, in denen Messwerte publiziert werden. "
                "Diese werden dann an ein Kafka-Topic gesendet, wo andere Applikationen darauf zugreifen können. "
                "Eine zweite kleine Applikation greift die Daten ab, transformiert sie und schreibt die transformierten "
                "Daten in eine Datenbank. Zusätzlich wird eine Webapplikation erstellt, welche dank Datenbankzugriff "
                "Visualisierungen der Live-Daten ermöglicht. Die Applikationen laufen in Docker-Containern und es gibt "
                "eine zentrale Verwaltung der Logging-Informationen der Applikation. "
                "Hinweis im Dokument: hier sollen noch passende Grafiken und ggf. mehr Details ergänzt werden "
                "(welcher Service was macht, Logging/Monitoring, eingesetzte Technologien usw.)."
            ),
            "steps_already_taken": (
                "Nur ein paar Code-Ausschnitte aus dem CAS Data Engineering "
                "(Templates, Projektarbeiten) und Ideen zur Umsetzung einzelner Elemente."
            ),
            "call_to_action": "Eine Woche Zeit für die Umsetzung.",
        },
    },
}

cas_data_engineering_context["llm_summary"] = """
CAS Data Engineering, Frühlingssemester 2026, FHNW.

Es gibt drei Hauptquellen:
1. Semester-Terminplan mit Modulen, Feiertagen, Reserveterminen und Räumen.
2. Leistungsbeurteilung mit Prüfungen, Projektarbeiten, Gruppengrössen und Modalitäten.
3. Richtlinien für die Use-Case-Präsentation am Abschluss.

Wichtige Prüfungs-/Abgabedaten:
- Software-Engineering Projektarbeit Note: 23.04.2026 23:59:59
- Data Wrangling Projektarbeit Testat: 22.05.2026
- Big Data Projektarbeit Note: 04.06.2026
- Containerisierung Prüfung: 27.06.2026, vorgezogen 28.03.2026
- Data Science Prüfung: 27.06.2026
- Cloud Grundlagen Projektarbeit Testat: 27.06.2026 08:30
- Architektur Projektarbeit Testat: 27.06.2026 08:30
- Eigener Use-Case Testat/Präsentation: 27.06.2026

Wichtige Regeln:
- Projektarbeiten sind optional, aber wenn abgegeben, werden sie benotet und zählen zur Gesamtnote.
- Der eigene Use-Case muss am Ende präsentiert werden.
- Die Gesamtnote ist der Mittelwert aus Prüfungen und allen benoteten Projektarbeiten.

Use-Case-Präsentation:
- Maximal 10 Slides
- 10 Minuten
- Es muss nichts umgesetzt werden
- Ziel ist ein überzeugender Pitch einer Lösungsidee unter Einbezug von CAS-Modulen
- Typische Struktur: Warum jetzt, was passiert ohne Änderung, Problem, Lösung, bisherige Schritte, Call-to-Action
"""

config: dict = {
    "system_prompt": "",
    "temperature": 0.7,
    "model": "gpt-5-mini",
}

context_manager = CASContextManager(cas_data_engineering_context, config)
