# kintai Reference Guide (English)

## Environment Setup

### .env File

Create a `.env` file at the project root or home directory:

```
LEVTECH_EMAIL=your-email@example.com
LEVTECH_PASSWORD=your-password
```

**Important**: Add `.env` to `.gitignore`. Never commit credentials to the repository.

### Cookie Storage

- Path: `/tmp/kintai-cookies.json`
- Format: Browser automation tool's cookie JSON format
- Cleared on OS restart (re-login required)

## Authentication Flow

### Google Login Steps

```
1. Navigate to https://platform.levtech.jp
   - Wait for page load

2. If login page is displayed:
   a. Find and click "Google Login" button
      - Selector: button/link containing text "Google"
   b. On Google login page:
      - Enter email in the email field
      - Click "Next" button
      - Wait for password screen to load
      - Enter password in the password field
      - Click "Next" button
   c. Wait for redirect:
      - Wait until URL returns to platform.levtech.jp
      - Confirm dashboard or work report page is displayed

3. Verify login success:
   - Confirm username is displayed on the page
   - Save cookies to /tmp/kintai-cookies.json
```

### Cookie Reuse

```
1. Check if /tmp/kintai-cookies.json exists
2. If exists:
   a. Load cookies into browser session
   b. Navigate to https://platform.levtech.jp/p/workreport/
   c. If redirected to login → cookies invalid → re-login
   d. If work report page loads → cookies valid → continue
3. If not exists:
   → Execute Google login flow
```

## Browser Operations

### Work Report List → Detail Page

```
URL: https://platform.levtech.jp/p/workreport/

1. Find current month link in the table
   - Text example: "2026/03"
   - Click the link

2. Navigate to detail page
   - URL pattern: /p/workreport/input/{id}/
   - Page title contains "作業報告書詳細"
```

### Detail Page → Edit Mode

```
1. Find and click the "Edit" button
   - Text: "編集する"
   - Wait for input fields to appear

2. Confirm edit mode:
   - "Save" button ("保存する") is visible
   - Input fields are displayed in date rows
```

### Date Row Identification and Input

```
1. Scan table rows
   - First cell contains date text (e.g., "03/04", "03/04（水）")
   - Find the row matching the target date

2. Identify input fields:
   - Get input elements in order within the row
   - 1st: start time (e.g., "10:00")
   - 2nd: end time (e.g., "19:00")
   - 3rd: break duration (e.g., "01:00")

3. Enter values:
   - Click each field to focus
   - Clear existing value, then type new value
   - Tab to next field if needed

4. Save:
   - Click "Save" button ("保存する")
   - Wait for page reload/update
   - Take screenshot and display to user
```

### Check Mode Operations

```
1. Read the detail page table (view mode)
   - Do NOT click "Edit"
2. Check "Start" column (2nd column) of each row
   - Has value → filled
   - Empty → not filled
3. Collect filled dates
4. Display results as text:
   "Filled days: 3/3 (Tue), 3/5 (Thu), 3/7 (Sat) — 3 days total"
```

## Troubleshooting

### Cannot Login

- Verify email and password in `.env`
- Check that 2FA is not enabled on the Google account (2FA is not supported)
- Delete cookie file and retry: `rm /tmp/kintai-cookies.json`

### Month Link Not Found

- Verify the work report list URL is correct
- Check that the current month's report exists in the Levtech admin

### Date Row Not Found

- Confirm the target date is within the current month
- Verify date format is correct (M/D format: 3/4, 12/25, etc.)

### Save Fails

- Confirm edit mode is active ("Save" button visible)
- Verify input values are in correct format (HH:MM)
