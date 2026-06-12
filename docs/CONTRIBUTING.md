# Contributing to JRTreborn

Thank you for helping keep JRTreborn up to date! The most impactful contributions are new junkware signatures.

---

## Adding a New Program Signature

Edit `database/programs.json` and add an entry to the `programs` array:

```json
{
  "name": "Display Name",
  "match": ["ExactName", "Alternate Name", "AnotherVariant"],
  "publisher": "Publisher Name"
}
```

**Fields:**
- `name` — Human-readable name shown in reports
- `match` — Array of strings to match against the installed program's `DisplayName` (substring, case-insensitive)
- `publisher` — Optional, for documentation purposes

**Guidelines:**
- Be specific enough to avoid false positives on legitimate software
- If the program has many name variants across versions, list them all in `match`
- Do NOT add legitimate software just because you dislike it

---

## Adding Registry Keys

Edit `database/registry.json` and add to the `keys` array:

```json
{
  "name": "Human-readable description",
  "path": "HKLM:\\SOFTWARE\\SomeAdware",
  "action": "remove_key"
}
```

For removing a single value instead of an entire key:

```json
{
  "name": "Adware autostart entry",
  "path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run",
  "value": "AdwareName",
  "action": "remove_value"
}
```

**Supported actions:** `remove_key`, `remove_value`

**Supported hives:** `HKLM:`, `HKCU:`

---

## Adding File/Folder Paths

Edit `database/files.json`. Use these environment variable placeholders:

| Placeholder | Expands to |
|-------------|-----------|
| `{ProgramFiles}` | `C:\Program Files` |
| `{ProgramFiles(x86)}` | `C:\Program Files (x86)` |
| `{AppData}` | `%APPDATA%` (roaming) |
| `{LocalAppData}` | `%LOCALAPPDATA%` |
| `{ProgramData}` | `C:\ProgramData` |
| `{CommonProgramFiles}` | `C:\Program Files\Common Files` |
| `{Windows}` | `C:\Windows` |

Folder entry:
```json
{ "name": "Adware folder", "path": "{ProgramFiles(x86)}\\AdwareName" }
```

File entry (under `"files":`):
```json
{ "name": "Adware DLL", "path": "{Windows}\\system32\\adware.dll" }
```

---

## Adding Browser Hijacker URLs

Edit `database/browsers.json`. Add to `homepage_hijackers`:

```json
"hijacker-domain.com"
```

The scanner checks if any browser homepage or startup URL contains this string (substring match).

---

## Adding Known Extension IDs

For Chrome/Edge/Brave, add to `chrome_extension_ids`:

```json
{ "id": "abcdefghijklmnopqrstuvwxyz123456", "name": "Malicious Extension Name" }
```

For Firefox, add to `firefox_extension_ids`:

```json
{ "id": "extension@domain.com", "name": "Malicious Extension Name" }
```

**Important:** Only add extensions that are definitively malicious or unwanted. Do not add legitimate extensions.

---

## Adding Processes, Services, Tasks

These follow the same pattern. See the existing entries in each JSON file as examples.

---

## Testing

Before submitting a PR:

1. Run `.\JRTreborn.ps1 -DryRun` to verify your signature is detected
2. Verify the detection is a true positive (the program is actually junkware)
3. Verify no legitimate programs are matched by your new entry

---

## Pull Request Process

1. Fork the repository
2. Create a branch: `git checkout -b add/adware-name`
3. Make your changes to the JSON database files
4. Test with `-DryRun`
5. Submit a PR with a brief description of what was added and why it's junkware

---

## Reporting Junkware Not Yet Covered

Open an issue with:
- Program name and publisher
- How it installs (bundled with what, downloaded from where)
- What it does (browser hijack, adware, bloatware, etc.)
- Screenshot of it in Programs & Features if possible

We'll research it and add it to the database.
