# JRTreborn — Junkware Removal Tool Reborn

**A free, open source, portable tool for removing adware, junkware, and bloatware from Windows 10 and Windows 11.**

Inspired by the original JRT (Junkware Removal Tool) before it was acquired by Malwarebytes, JRTreborn picks up where it left off — actively maintained, community-driven, and always free.

---

## Download

**[⬇ Download JRTreborn.exe from the latest Release](https://github.com/delanderdev/jrtreborn/releases/latest)**

No installation required. Just download and run.

---

## Features

- **Single .exe — no installation** — download, double-click, done
- **Auto UAC elevation** — prompts for admin rights automatically
- **Comprehensive detection** covering:
  - Known adware and PUP programs (300+ signatures)
  - Registry keys and autostart entries
  - Malicious scheduled tasks and Windows services
  - Browser homepage, new tab, and search engine hijacks (Chrome, Edge, Brave, Firefox)
  - Malicious browser extensions (Chrome, Edge, Firefox)
  - Internet Explorer BHOs
  - **Browser Group Policy hijacks** — force-installed extensions and locked homepages via registry policies
  - Junk files and folders
- **Safety first** — creates a System Restore Point before any removal
- **Dry Run mode** — preview what would be removed without making changes
- **HTML report** — clean visual report saved to your Desktop after every scan
- **Community-updated database** — plain JSON signature files anyone can contribute to via PR

---

## Requirements

- Windows 10 or Windows 11
- Administrator privileges (the exe will prompt automatically)

---

## Quick Start

### Option A: Download the exe (easiest — recommended for end users)

1. Go to [Releases](https://github.com/delanderdev/jrtreborn/releases/latest)
2. Download `JRTreborn.exe`
3. Double-click it
4. Click **Yes** on the UAC prompt
5. Choose **Scan and Remove** from the menu

### Option B: Run from source (for developers / contributors)

Right-click `Run-JRTreborn.bat` → **Run as administrator**

### Option C: PowerShell directly

```powershell
# Run as Administrator, then:

# Interactive mode (menu-driven)
.\JRTreborn.ps1

# Scan only (no changes made)
.\JRTreborn.ps1 -Scan

# Scan and remove everything detected
.\JRTreborn.ps1 -Remove

# Preview mode (shows what would be removed, no changes)
.\JRTreborn.ps1 -DryRun
```

If you get an execution policy error, run this first:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

---

## How It Works

```
JRTreborn.ps1          ← Main launcher, user interface
├── src/
│   ├── Scanner.ps1    ← Detection engine
│   ├── Remover.ps1    ← Removal engine
│   ├── Logger.ps1     ← Logging and HTML report
│   └── RestorePoint.ps1 ← Safety restore point
└── database/
    ├── programs.json  ← Known adware/PUP programs
    ├── registry.json  ← Registry keys to clean
    ├── files.json     ← Files/folders to remove
    ├── processes.json ← Processes to terminate
    ├── services.json  ← Services to delete
    ├── tasks.json     ← Scheduled tasks to remove
    └── browsers.json  ← Browser hijacker URLs & extension IDs
```

**Scan order:**
1. Terminate known adware processes
2. Stop and delete known adware services
3. Remove malicious scheduled tasks
4. Uninstall known adware programs via their uninstaller
5. Clean registry keys and startup entries
6. Delete leftover files and folders
7. Reset browser homepages and remove malicious extensions
8. Generate HTML report

---

## Database Updates

The signature database lives in the `database/` folder as plain JSON files. Anyone can:

1. Add a new program to `programs.json`
2. Add registry keys to `registry.json`
3. Add browser hijacker URLs to `browsers.json`
4. Submit a pull request

See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for the full database schema and guidelines.

---

## Safety

- **Always creates a System Restore Point** before removal (can be disabled with `-NoRestorePoint`)
- **Dry Run mode** lets you preview all changes before committing
- **Open source** — you can audit every line before running it
- Does not phone home, collect telemetry, or require an internet connection
- Will never flag or remove legitimate software that isn't in the database

---

## Output

After every scan, JRTreborn saves two files to your Desktop:

- `JRTreborn_YYYY-MM-DD_HH-MM-SS.log` — plain text log
- `JRTreborn_YYYY-MM-DD_HH-MM-SS.html` — color-coded visual report (opens automatically)

---

## FAQ

**Q: Does this replace antivirus software?**
No. JRTreborn targets adware, PUPs, and browser hijackers specifically. It is a complement to, not a replacement for, a proper antivirus tool.

**Q: Is it safe to run on a production system?**
Yes, with the restore point. We recommend using Dry Run first on any system you're unsure about.

**Q: The tool says "no threats found" but my browser is still hijacked.**
The hijacker may not be in our database yet. Please [open an issue](https://github.com/delanderdev/jrtreborn/issues) with details and we'll add it.

**Q: Can I run this without admin rights?**
Scan-only mode works without admin. Removal requires admin privileges to stop services, delete registry keys, and uninstall programs.

---

## Contributing

Contributions welcome! The most valuable thing you can do is add signatures for junkware you encounter in the wild.

See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for details.

---

## License

MIT License. See [LICENSE](LICENSE).

---

## Disclaimer

JRTreborn is provided as-is, without warranty of any kind. Always maintain backups and use Dry Run mode before removing items from systems you're not familiar with. The authors are not responsible for any unintended consequences of use.
