# Init Phase — Requirements Generation

## Overview

Generate a requirements document (requirement.md).
Extract and organize requirements from user dialogue or existing conversation history.

## Execution Steps

### 1. Context Check

```
Conversation history exists → Extract requirements from conversation
No conversation history → Explore requirements through dialogue
--quick specified → Infer and generate from project description
--analyze specified → Analyze existing codebase
```

### 2. Existing Project Analysis (--analyze)

When existing code is present:
```bash
find . -type f -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.java" -o -name "*.go" | head -20
```

Analysis targets:
- Project structure and architecture
- Existing features
- Dependencies and tech stack
- Code patterns and conventions

### 3. Dialogue Mode (AskUserQuestion)

**Principle: Use AskUserQuestion for any question that can be presented as choices.**
Use text questions only for open-ended inputs (project name, concept description, etc.).

#### Standard Dialogue

Collect information progressively using AskUserQuestion.
Adjust the number of rounds based on project complexity.

**Round 1: Basic Information (3–4 questions simultaneously)**

```
Q1: "What type of project is this?"
header: "Type"
options:
  - "Web App" / "Frontend + Backend"
  - "API Server" / "Backend only"
  - "CLI Tool" / "Command-line tool"
  - "Mobile App" / "iOS/Android"

Q2: "What's the project scale?"
header: "Scale"
options:
  - "Small (1–2 screens, a few features)"
  - "Medium (5–10 screens, multiple domains)"
  - "Large (10+ screens, complex domain)"

Q3: "Who are the target users?"
header: "Users"
options:
  - "Personal / Just me"
  - "Team / Internal use"
  - "Public / B2C"
  - "Enterprise / B2B"

Q4: "Is authentication required?"
header: "Auth"
options:
  - "Not needed"
  - "Basic auth (email + password)"
  - "Social login included"
  - "SSO / Enterprise auth"
```

**Round 2: Tech Stack (adjusted based on Round 1 answers)**

For web apps:
```
Q1: "Frontend framework?"
header: "Frontend"
options:
  - "Next.js (Recommended)"
  - "React (SPA)"
  - "Vue / Nuxt"
  - Undecided → Other

Q2: "Database?"
header: "Database"
options:
  - "PostgreSQL (Recommended)"
  - "MySQL"
  - "MongoDB"
  - "SQLite (for small scale)"

Q3: "Deployment target?"
header: "Deploy"
options:
  - "Vercel / Netlify"
  - "AWS / GCP"
  - "Docker / Self-hosted"
  - "Undecided"
```

**Round 3 (only if needed): Additional Requirements**

```
Q1: "Is internationalization (i18n) needed?"
header: "i18n"
options:
  - "Not needed"
  - "Two languages (EN/JA)"
  - "Three or more languages"

Q2: "Any other important requirements?" → multiSelect: true
header: "Features"
options:
  - "Real-time updates"
  - "File uploads"
  - "Email notifications"
  - "External API integrations"
```

**Notes:**
- If Round 1 answers make the project sufficiently clear, proceed to generation after Round 2
- If Round 2 leaves no open questions, skip Round 3
- If the user chooses "Other" with free text, ask follow-up questions if needed

#### Socratic Deep-Dive (--deep)

Explore from fundamentals using AskUserQuestion. Uses more rounds than standard.

```
Round 1: Purpose and Motivation
Q1: "What's the #1 problem this project solves?"
Q2: "How are you currently dealing with this problem?"

Round 2: Users and Value (based on Round 1 answers)
Q1: "Who benefits the most from this?"
Q2: "What's the first thing a user would do with this tool?"

Round 3: Constraints and Priorities
Q1: "What's the most important quality attribute?"
  options: Performance / Security / Usability / Extensibility
Q2: "What must absolutely be avoided?"
```

#### Multi-Perspective Analysis (--personas)

Evaluate requirements from 7 perspectives:

| Persona | Focus Area |
|---------|-----------|
| Architect | System design, extensibility, maintainability |
| Analyst | Data flow, bottlenecks, optimization |
| Frontend | UI/UX, responsiveness, accessibility |
| Backend | API design, data processing, performance |
| Security | Vulnerabilities, auth/authz, data protection |
| DevOps | Deployment, monitoring, scalability |
| PM | Schedule, resources, risk management |

### 4. Generate requirement.md

#### Output Structure

```markdown
# Requirements Document — [Project Name]

## 1. Overview
Project purpose and background

## 2. Functional Requirements
[REQ-001] Feature name
- Detailed description
- User story

[REQ-002] Feature name
...

## 3. Non-Functional Requirements
[NFR-001] Performance requirements
[NFR-002] Security requirements
...

## 4. Constraints
[CON-001] Technical constraints
[CON-002] Business constraints
...

## 5. Assumptions
[ASM-001] Assumption
...

## 6. Glossary
Domain-specific term definitions
```

#### ID Prefixes

| Prefix | Meaning |
|--------|---------|
| REQ-XXX | Functional requirement |
| NFR-XXX | Non-functional requirement |
| CON-XXX | Constraint |
| ASM-XXX | Assumption |

### 5. Output Location

```
.specs/[project-name]/requirement.md
```

Project names are converted to English kebab-case.

## YAGNI Checklist

Do **not** include unless explicitly requested:

- [ ] Complex permission management
- [ ] Advanced analytics/reporting
- [ ] API versioning
- [ ] Multi-tenant support
- [ ] Real-time notifications/updates
- [ ] Social login
- [ ] Detailed audit logging
- [ ] Data migration plans
- [ ] Batch processing / scheduled jobs
- [ ] Async processing
