# Changelog

All notable changes to JRTreborn will be documented here.

---

## [1.2.0] - 2026-06-13

### Build System
- Replaced `ps2exe` with a native C# launcher (`build/Launcher.cs` + `build/Launcher.manifest`) compiled via `csc.exe` — no PowerShell Gallery dependency in CI and no ps2exe heuristic AV fingerprint. The exe embeds the standalone script as compressed base64, extracts it to a temp file at runtime, runs it elevated (UAC via manifest), and cleans up on exit

### Detection Database v1.2.0 (curated expansion)
- **browsers.json** (+61 homepage hijackers): searchmine, searchbaron, searchmarquis, coolwebsearch, omiga-plus, holasearch, searchgol, mixidj, anysearchmanager, dosearches, Mindspark hijack domains (mapsgalaxy, televisionfanatic, pdfconverterhq, weatherblink, packtrackplus, etc.) and more
- **programs.json** (+39): Yontoo, Superfish, PremierOpinion, OpenCandy, InstallCore, DealPly, Linkury/SmartBar, Wajam, Mobogenie, Baidu PC Faster, PriceMeter, SavingsBull, eFast, BoBrowser, OptimizerPro, RegClean Pro, SlimCleaner, and Mindspark toolbar variants
- **registry.json** (+21): vendor keys and Run values for Yontoo, Superfish, Linkury, SmartBar, DealPly, InstallCore, Amonetize, PriceMeter, SavingsBull, Mobogenie, Baidu, eFast, BoBrowser, Systweak, OptimizerPro, WebDiscover, Wajam, DNS Unlocker
- Note: extension IDs and BHO CLSIDs were intentionally **not** bulk-expanded — unverified identifiers in a removal tool risk deleting legitimate browser extensions

### Program Scan — Coverage Engine
- **Publisher-based detection** — `programs.json` now has a `publishers` list; a single rule (e.g. "Mindspark Interactive Network", "Conduit", "Spigot") matches every product from that vendor, current and future
- **Field-broadened matching** — distinctive program patterns (≥5 chars) now also match the install location, not just the display name
- **Heuristic "Suspected" tier** — generic PUP-category patterns ("Driver Updater", "Registry Cleaner", "PC Optimizer", "Toolbar", "Coupon", …) flag unknown programs as low-confidence *Suspected*. Suspected items are shown separately, **never auto-removed**, and require explicit confirmation (interactive prompt) or the new `-IncludeSuspected` switch
- **Trusted-vendor allowlist** — a publisher allowlist (Microsoft, Intel, NVIDIA, Dell, Google, Mozilla, …) globally suppresses detections for legitimate software, applied to *every* route including known signatures
- **Appx/MSIX scan** — `Get-AppxPackage` enumeration flags known Store bloatware (Candy Crush, etc.) as Suspected, removable via `Remove-AppxPackage`
- **Signature enrichment** — Suspected items note when their main binary is unsigned/untrusted
- Reports and the console now separate **Known** vs **Suspected** detections, with a new `SUSPECT` log category and HTML styling

### Bug Fixes (pre-existing, surfaced by PowerShell AST validation)
- **Browser group-policy scanner never ran** — `Invoke-PolicyScan` was accidentally nested inside `Invoke-BrowserScan` (brace mismatch), so it was out of scope when called and the v1.1.0 policy feature silently did nothing. Lifted to a top-level function
- **Main script could not parse** — `Show-InteractiveMenu` used `return switch {…}`, which is invalid PowerShell; the interactive menu (and thus the whole script) failed to load. Changed to assign-then-return
- **Standalone build produced an invalid script** — the merge inlined the main script's `[CmdletBinding()] param()` block mid-file, where `param` is illegal. `Merge-Script.ps1` now hoists it to the top of the standalone
- **Over-broad signature** — the `DriverUpdate` rule matched `"Driver Update"`, flagging any "…Driver Updater" (including legitimate OEM tools) as known junkware; narrowed to Slimware-specific patterns so generic ones fall through to the Suspected tier

---

## [1.1.0] - 2026-06-13

### Build System
- Single-file `JRTreborn.exe` — all source files and the full detection database are compiled into one portable executable
- New `build/Merge-Script.ps1` — merges `src/*.ps1` modules and embeds all `database/*.json` files as compressed base64 strings into a standalone `.ps1`
- New `build/Build-Exe.ps1` — compiles the merged script to a Windows exe using `ps2exe`, with admin-required UAC manifest and full version metadata
- New `.github/workflows/build-release.yml` — GitHub Actions CI workflow on `windows-latest` that builds the exe on every push to `main` and publishes it as a GitHub Release asset when a `v*` tag is pushed

### Bug Fixes
- Fixed: `DryRun` flag was not propagated to `Reset-FirefoxHijack` — Firefox homepages were being reset even in scan-only/dry-run mode
- Fixed: `takeown` and `icacls` paths were unquoted — removal failed silently on adware folders with spaces in the path
- Fixed: Chrome `Preferences` JSON was overwritten without a backup and without checking if the browser was running — could corrupt the profile
- Fixed: `$args` PowerShell automatic variable was shadowed in the re-elevation code path
- Fixed: HTML report header embedded `$env:COMPUTERNAME` and username without HTML-encoding — potential injection in report output
- Fixed: No null guard on `$entry.display` in the service scanner — could false-match services with a missing display name field
- Fixed: "FileZilla (bundled)" program entry incorrectly matched "Relevant Knowledge" — wrong program entirely
- Fixed: Duplicate DealPly Chrome extension ID in `browsers.json`

### New Feature — Browser Group Policy Scanner
- New `database/policies.json` describing Chrome/Edge enterprise policy registry paths used by adware
- `Invoke-PolicyScan` checks `ExtensionInstallForcelist` keys for known-bad extension IDs and flags homepage/new-tab/search override policy values
- `Remove-PolicyExtension` and `Remove-PolicyValue` remove specific policy values (not the whole key, to preserve legitimate IT-managed policies)

### Detection Database v1.1.0 (~700 new signatures)
- **programs.json** (+80): Elex/CrossRider family, PC App Store, Reimage Repair, Driver Easy, SafeFinder, Vonteera, RocketTab, Shopperz, Pirrit, rogue AV (TotalAV, Security Shield, Smart Fortress), Mindspark toolbar variants, and more
- **registry.json** (+40): CrossRider/GlobalUpdate/Elex registry keys, modern adware run values, Chrome/Edge group policy override entries
- **browsers.json** (+65 hijacker domains, +17 Chrome extension IDs, +10 Firefox extension IDs, +8 IE BHO CLSIDs)
- **processes.json** (+38), **services.json** (+16), **tasks.json** (+22), **files.json** (+35 folders, +7 startup patterns)

---

## [1.0.0] - 2026-06-12

### Initial Release

- Full scan engine covering processes, services, scheduled tasks, installed programs, registry, files, and browsers
- 200+ known adware/PUP program signatures
- 90+ registry key/value signatures
- 80+ file system path signatures
- 40+ scheduled task signatures
- 25+ Windows service signatures
- 50+ browser hijacker URL patterns
- Chrome, Edge, Brave, and Firefox browser extension detection
- Internet Explorer BHO detection
- System Restore Point creation before any removal
- Dry Run mode
- Color-coded terminal output
- HTML scan report with dark theme
- Plain text log file
- Interactive menu for non-technical users
- Command-line parameter support for scripted/tech use
- Batch file launcher (`Run-JRTreborn.bat`)
