# Changelog

All notable changes to JRTreborn will be documented here.

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
