# Security and privacy

This skin is local-first. It does not use OAuth, cloud APIs, telemetry, or remote accounts.

- ActivityWatch access is optional and limited to the configured local endpoint (`http://localhost:5600`).
- Todo writes are limited to the configured local Markdown file and use hash conflict protection, validation, backup, and atomic replacement.
- PowerShell helpers are launched hidden by Rainmeter and their source is included in this repository.
- Quick Launch only starts commands explicitly present in its local configuration.

Before installing an untrusted fork, inspect its `.ps1`, `.lua`, `.bat`, and `.ini` files. This project does not ship a code-signed `.rmskin`.

Please report security issues through GitHub Issues without posting sensitive local data.
