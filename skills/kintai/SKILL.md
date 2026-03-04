---
name: kintai
description: |
  Automate Levtech platform (platform.levtech.jp) time tracking input via browser automation.
  Records work start/end times and break duration for daily work reports.

  Triggers:
  - "/kintai", "/kintai check"
  - 「勤怠入力」「作業報告」「レバテック」
license: MIT
---

# kintai — Levtech Time Tracking Automation

Automate daily time entry on the Levtech platform work report system using browser automation tools.

## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese output, use `references/guide.ja.md` for detailed steps
3. English input → English output, use `references/guide.md` for detailed steps
4. Explicit override takes priority

## Commands

| Command | Description |
|---------|-------------|
| `/kintai` | Interactive mode — confirm defaults and register today |
| `/kintai HH:MM HH:MM HH:MM` | Quick mode — register today with start, end, break |
| `/kintai M/D HH:MM HH:MM HH:MM` | Date mode — register specific date |
| `/kintai check` | Show filled days for current month |

**Defaults**: Start 10:00, End 19:00, Break 01:00

## Execution Flow

### Step 1: Parse Arguments

```
args == "" or null          → Interactive Mode (Step 2a)
args == "check"             → Check Mode (Step 5)
args matches "HH:MM HH:MM HH:MM"
                            → Quick Mode: date=today (Step 2b)
args matches "M/D HH:MM HH:MM HH:MM"
                            → Date Mode (Step 2b)
otherwise                   → Show help message
```

Get today's date:
```bash
date +%m/%d
```

### Step 2a: Interactive Mode

Display today's date and default values, then ask:

```
AskUserQuestion:
  question: "Register today ({date}) with these values?" /
            "今日 ({date}) の勤怠を登録します。"
  header: "Kintai"
  options:
    - "Register with defaults (10:00-19:00, break 01:00)" /
      "デフォルト値で登録（10:00-19:00、休憩01:00）"
    - "Change times" / "時間を変更"
    - "Cancel" / "キャンセル"
```

- If "Register with defaults" → set start=10:00, end=19:00, break=01:00, proceed to Step 3
- If "Change times" → ask user for values as text, then proceed to Step 3
- If "Cancel" → exit

### Step 2b: Quick/Date Mode

Parse the arguments directly:
- Quick: `{start} {end} {break}`, date = today
- Date: `{month}/{day} {start} {end} {break}`

Proceed to Step 3.

### Step 3: Authentication

Load credentials from `.env` file (see reference guide for `.env` format):
- `LEVTECH_EMAIL` — Google login email
- `LEVTECH_PASSWORD` — Google login password

If either is missing, show error and exit:
> "Set LEVTECH_EMAIL and LEVTECH_PASSWORD in .env file."

**Cookie check**: Look for saved cookies at `/tmp/kintai-cookies.json`.

- If cookies exist → load them into the browser session
- If no cookies or session expired → perform Google login flow:
  1. Navigate to `https://platform.levtech.jp`
  2. Click Google login button
  3. Enter email → click Next
  4. Enter password → click Next
  5. Wait for redirect back to Levtech
  6. Save cookies to `/tmp/kintai-cookies.json`

See the reference guide for detailed browser automation steps.

### Step 4: Navigate and Input

1. Navigate to `https://platform.levtech.jp/p/workreport/`
2. Find and click the current month's link (e.g., text containing "2026/03")
3. On the detail page, click the "Edit" button (text: "編集する")
4. Wait for the edit form to load
5. Find the target date row in the table:
   - Search for the row containing the target date text (e.g., "03/04")
6. Fill in the input fields for that row:
   - 1st field: start time
   - 2nd field: end time
   - 3rd field: break duration
7. Click the "Save" button (text: "保存する")
8. Wait for save to complete
9. Take a screenshot and display to user for confirmation

Existing values in the target date row will be overwritten without confirmation.

See the reference guide for detailed selector and wait strategies.

### Step 5: Check Mode

1. Authenticate (same as Step 3)
2. Navigate to work report list → click current month
3. Read the detail page table
4. Collect dates where the "Start" column has a value
5. Display results:

```
Filled days this month:
  3/3 (Tue), 3/5 (Thu), 3/7 (Sat) — 3 days total
```

### Step 6: Error Handling

| Error | Message |
|-------|---------|
| .env not configured | "Set LEVTECH_EMAIL and LEVTECH_PASSWORD in .env" |
| Login failed | "Google login failed. Check your credentials." |
| Month link not found | "Current month's work report not found." |
| Date row not found | "Input row for {date} not found." |
| Save button not found | "Save button not found. Edit mode may not be active." |

On any browser automation error, take a screenshot for debugging before reporting the error.
