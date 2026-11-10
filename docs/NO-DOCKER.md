# Why no Docker

This lab’s goal is **instant re-setup of a bare Debian PC** with predictable RAM and CPU use.

Containers add a permanent daemon, image layers, and often a second copy of runtimes. On small or older machines that cost is too high for the benefit when the workload is “install apt packages + a few .debs + systemd services.”

Bootstrap therefore:

- installs packages with `apt` only
- never runs `docker`, `podman`, or compose
- never pulls container images

If a product later needs isolation, prefer a second user account, systemd unit hardening, or a separate VM — not Docker on this host by default.
