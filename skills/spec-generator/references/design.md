# Design Phase — Design Document Generation

## Overview

Generate a technical design document (design.md).
Takes requirement.md as input to create architecture, class design, and data flow.

## Execution Steps

### 1. Locate Requirements File

```bash
find .specs -name "requirement.md" -type f
```

Extract from requirements file:
- Functional requirements (REQ-XXX)
- Non-functional requirements (NFR-XXX)
- Constraints (CON-XXX)

### 2. Check for coding-rules.md

If `docs/coding-rules.md` exists (or an alternative path specified in CLAUDE.md / AGENTS.md), read it before designing:

- Extract `[MUST]` rules as hard constraints for the design
- Use `[SHOULD]` rules (including skill-derived rules marked `Source: skill/*`) as design recommendations
- Ensure naming conventions, test strategy, and technology choices align with the rules
- Reference coding-rules.md in the "Implementation Guidelines" section of design.md

### 3. Create Existing Asset Map

Check existing assets before new implementation (avoid reinventing the wheel):

```bash
# Shared components
find . -type d \( -name "shared" -o -name "common" -o -name "components" \) -not -path "*/node_modules/*"

# Existing services/modules
find . -type f \( -name "*Service*" -o -name "*Repository*" -o -name "*Controller*" \) -not -path "*/node_modules/*"

# Auth-related
find . -type f \( -name "*auth*" -o -name "*Auth*" \) -not -path "*/node_modules/*"

# Data models
find . -type d \( -name "models" -o -name "types" -o -name "entities" \) -not -path "*/node_modules/*"
```

If code intelligence tools are available in your environment, use them for deeper analysis of symbols, classes, and module relationships.

### 4. Design Decisions (AskUserQuestion)

When requirement.md alone doesn't determine the technical choices, confirm with AskUserQuestion.

**Architecture selection (when multiple patterns are viable):**
```
Q1: "Architecture pattern?"
header: "Architecture"
options:
  - "Monolith (simple, small–medium scale)"
  - "Modular monolith (prepared for future separation)"
  - "Microservices (large scale, distributed teams)"

Q2: "API design style?"
header: "API Style"
options:
  - "REST API (Recommended)"
  - "GraphQL"
  - "tRPC (full-stack TypeScript)"
```

**State management (frontend):**
```
Q1: "State management approach?"
header: "State"
options:
  - "Server state focused (TanStack Query, etc.) (Recommended)"
  - "Global state management (Zustand, Redux, etc.)"
  - "Framework built-in only (Context API, etc.)"
```

**Note:** Skip if technology choices are already specified in requirement.md.

### 5. Generate Design Document

#### Output Structure

```markdown
# Technical Design Document — [Project Name]

## 1. Requirements Traceability Matrix

| Req ID | Requirement | Design Component | Existing Asset | New Reason |
|--------|------------|-----------------|---------------|-----------|
| REQ-001 | User auth | AuthService | Reuse existing | - |
| REQ-002 | Data mgmt | DataAPI | New | Special requirements |

## 2. Architecture Overview

### 2.1 System Architecture Diagram
[Mermaid diagram]

### 2.2 Component Interactions
[Sequence diagram]

## 3. Technology Stack

- Language: [Language vX.X]
- Framework: [FW vX.X]
- Database: [DB vX.X]
- Other dependencies

## 4. Module / Class Design

### [REQ-001] Feature Name
> Requirement: "Quote from requirement.md"

Design:
- Class/module structure
- Public interfaces
- Dependencies

## 5. Data Design

### 5.1 Data Model
[ER diagram or schema definition]

### 5.2 Data Flow
[Data flow diagram]

## 6. Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Auth method | JWT | Statelessness |
| Database | PostgreSQL | ACID guarantees |

## 7. Implementation Guidelines

- Coding conventions
- Testing strategy
- Deployment considerations
```

### 6. Multi-Perspective Review (--personas)

Evaluate the design from 7 expert perspectives:

| Persona | Review Focus |
|---------|-------------|
| Architect | System consistency, extensibility, technical debt |
| Backend | API design, data processing, error handling |
| Frontend | Component reusability, state management |
| Security | Auth/authz, encryption, vulnerability mitigation |
| DevOps | Deployment ease, monitoring, scalability |
| DB Engineer | Schema optimization, indexes, transactions |
| QA Engineer | Testability, coverage, automation |

### 7. Visual Design (--visual)

Diagrams to generate:

```mermaid
# System Architecture
graph TB
    Client --> API
    API --> Service
    Service --> DB

# Class Diagram
classDiagram
    class Service {
        +method()
    }

# Sequence Diagram
sequenceDiagram
    User->>API: Request
    API->>Service: Process
    Service-->>API: Response

# ER Diagram
erDiagram
    User ||--o{ Order : has
```

### 8. Output Location

```
.specs/[project-name]/design.md
```

## Design Principles

### Requirements Traceability Required

- All design items must link to a requirement ID
- Do not include features not in the requirements
- Maximize reuse of existing assets

### YAGNI Check

Do **not** include unless explicitly specified in requirements:

- [ ] Monitoring/observability features
- [ ] Log collection/analysis systems
- [ ] Caching layer
- [ ] Async processing
- [ ] Admin dashboards
- [ ] Backup/restore functionality
