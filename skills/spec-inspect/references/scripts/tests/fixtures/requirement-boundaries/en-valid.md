# Requirements

## 1. Overview

Fixture.

## 2. Functional Requirements

### [REQ-001] Export a report

- Description: The service writes the selected report as CSV.
- Acceptance Criteria:
  - [ ] Selecting CSV produces one downloadable `.csv` file.

## 3. Non-Functional Requirements

### [NFR-001] Response time

- Description: Export completes within the documented limit.
- Acceptance Criteria:
  - [ ] A 10,000-row fixture completes within 5 seconds.

## 4. Constraints

Existing storage only.

## 5. Assumptions

The caller is authenticated.

## 6. Out of Scope

- PDF and spreadsheet export formats are not included.

## 7. Glossary

CSV: Comma-separated values.
