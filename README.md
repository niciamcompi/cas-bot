# CAS-Bot

A chatbot that allows users to ask questions about the content and schedule of the CAS Data Engineering course.

## Team

- Nicola
- Stephany
- Klaus

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

## Code / Architecture

TODO: Will be documented as the project progresses.
