# Security Boundaries

Default deny.

VCG never accepts arbitrary command text.
Every executable action maps to a named capability and a fixed handler.

Denied by design:
- arbitrary shell
- unrestricted PowerShell
- secret enumeration
- Real Repository direct write
- remote network pivot
- process injection
- credential scraping

Build/Test handlers only execute commands configured in
CONFIG/command_profiles.json.

Owner mode can grant profiles, not arbitrary commands.
