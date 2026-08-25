# Release verification

Artifact: `dist/TanaDaily-MistRainWorkbench-1.0.0.rmskin`

Verified: 2026-08-25 on Windows / Rainmeter

Size: 112,738 bytes

SHA-256: `958ADDAC286DD50C9F83E72A485BCD0FB12DB4B22EA18BDDEDAC7D616918A7BE`

## Safety and compatibility matrix

| Gate | Result | Verification |
|---|---:|---|
| Rainmeter package format | PASS | ZIP payload plus official 16-byte `RMSKIN` footer; stored ZIP size, flags, and magic verified |
| Rainmeter Skin Installer | PASS | Local `SkinInstaller.exe` accepted the package and displayed its confirmation UI; test closed it without installing |
| Archive integrity | PASS | Extracted package contained `RMSKIN.ini` and 46 skin files; every source file matched by SHA-256 |
| Manifest | PASS | Name, minimum versions, `LoadType=Skin`, and `MistRainWorkbench\MainDashboard.ini` load target verified |
| PowerShell syntax | PASS | All shipped `.ps1` files and the build script parsed with the Windows PowerShell parser |
| Lua 5.1 syntax | PASS | Every shipped `.lua` file parsed with `luaparse` |
| Encoding | PASS | Rainmeter UI/state includes use UTF-16LE BOM; writable Markdown/config data use UTF-8 BOM; Lua remains BOM-free |
| Todo toggle | PASS | Isolated fixture changed only the selected checkbox and produced a backup |
| Todo Chinese add | PASS | Added `測試中文新增任務 ✓`, preserved UTF-8 BOM, and successfully reparsed the result |
| Todo atomic safety | PASS | Writer validation and `.bak` behavior exercised in an isolated copy; live user data was not touched |
| ActivityWatch offline/no data | PASS | Unreachable local test endpoint produced the explicit no-data offline state |
| ActivityWatch last-known-good | PASS | Unreachable endpoint retained seeded prior data and produced the LKG offline state |
| Focus defaults | PASS | Four independent version-2 timer records decoded and validated at 25:00, stopped |
| Quick Launch defaults | PASS | Four config-driven categories decoded; no author-specific user path present |
| Desktop layer | PASS | Clock, Calendar, Todo, Focus, App Usage, and Quick Launch all set `ZPos -2` (`On Desktop`) |
| Privacy scan | PASS | No author tasks, ActivityWatch history, personal timer state, result/request cache, email, or `C:\Users\JSrad` path in the package |
| Network scan | PASS | Shipped scripts contain no unexpected remote endpoint; ActivityWatch default is localhost only |

## Scope note

The installer test intentionally stopped at Rainmeter's confirmation screen. It did not press **Install**, because the developer machine already has a live `MistRainWorkbench` installation and overwriting it would invalidate the data-preservation goal. Package parsing, archive structure, source integrity, state fixtures, and runtime helper behavior were tested independently.
