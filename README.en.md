# TanaDaily Rainmeter Skins

A local-first, low-permission Windows Rainmeter desktop workbench using neutral white / smoke-gray frosted glass.

## Demo

![TanaDaily Rainmeter Dashboard animated demo](screenshots/tanadaily-dashboard-demo.gif)

## Features

- Clock and monthly calendar
- Markdown Todo with direct checkbox toggling and an in-skin add panel
- Four independent, persistent Focus timers with a completion sound
- Optional read-only ActivityWatch integration via `localhost:5600`
- Configuration-driven Quick Launch with four renameable categories and five slots each
- `On Desktop` positioning so widgets stay behind normal applications

## Install

Requires Windows 10/11 and Rainmeter 4.5 or newer.

1. Download the latest `.rmskin` from [`dist`](dist/).
2. Double-click it and install with Rainmeter Skin Installer.
3. `MistRainWorkbench\MainDashboard.ini` loads and positions all six cards.

For a manual install, copy [`src/Skins/MistRainWorkbench`](src/Skins/MistRainWorkbench/) into your Rainmeter `Skins` directory and run **Refresh all**.

## Recommended: ActivityWatch

For **App Usage**, we recommend installing the [official ActivityWatch Windows Installer](https://activitywatch.net/downloads/)—choose the stable release and the recommended Installer download.

1. Install and start ActivityWatch.
2. Enable ActivityWatch at Windows startup so it can build a complete usage history.
3. Keep its default local endpoint at `http://localhost:5600`; the Dashboard reads it automatically without an account, OAuth, or cloud connection.

ActivityWatch remains optional. If it is missing or temporarily stopped, App Usage shows an offline state while every other widget keeps working.

## Data and privacy

Todo uses UTF-8 BOM Markdown and protects writes with source hashes, validation, an atomic replace, and a `.bak` backup. ActivityWatch is optional and only contacts the local service. The package contains no personal tasks, usage history, timer state, shortcuts, OAuth, telemetry, or cloud API integration. PowerShell and Lua sources are included for review; the `.rmskin` package is unsigned.

See [TESTING.md](TESTING.md) for verification details and [README.md](README.md) for the complete Traditional Chinese guide.

## License

[MIT](LICENSE)
