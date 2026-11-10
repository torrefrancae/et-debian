# Security / publish boundary

This repository is **public**. Treat every commit as world-readable.

## Never commit

- Passwords, API tokens, `.env` with real values
- SSH private keys, OpenVPN `.ovpn`, PKCS#12 / PEM with private material
- Agent packs, Cursor rules, Seatrix `global/rules` content
- Camera / NVR / AnyDesk / mail credentials
- Customer or production data dumps

## Safe patterns

- Use `.env.example` with empty placeholders only
- Put machine-local secrets under `private/` (gitignored)
- Download third-party installers at runtime; pin URLs in scripts, not blobs of secrets
- Prefer `ssh-copy-id` / `su` over baking credentials into the tree

## Privilege model

Bootstrap may need root. Preferred path:

1. Run as `et`
2. Elevate with `sudo` when `et` is in sudoers
3. Else `su -c '…'` with the root password (often same as `et`)

Do not embed passwords in scripts.
