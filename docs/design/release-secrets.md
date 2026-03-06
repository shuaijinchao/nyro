# Release Secrets (Desktop)

This project can build unsigned desktop artifacts by default.  
To enable production signing/notarization, configure these GitHub Actions secrets:

## macOS signing and notarization (optional but recommended)

- `APPLE_CERTIFICATE` (base64-encoded `.p12`)
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_TEAM_ID`

## Windows code signing (optional placeholder)

- `WINDOWS_CERTIFICATE` (base64-encoded `.pfx`/`.p12`)
- `WINDOWS_CERTIFICATE_PASSWORD`

Current workflow keeps Windows signing as a placeholder for a custom signing step.
