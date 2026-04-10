# Vector in the Hayabusa Windows Bundle

This package keeps Vector under the hood.

The Windows evaluator bundle does not currently ship a Vector binary by default. That is intentional for now:

- it keeps the bundle simple
- it avoids pretending Hayabusa already owns Windows packaging
- it lets a tester use either an installed Vector or a manually provided `vector.exe`

## Supported Paths

- installed Vector on the Windows host
- a manually downloaded `vector.exe` passed to:
  - `install.ps1 -VectorExePath C:\Path\To\vector.exe`

## Template Purpose

`vector.toml.tpl` uses Vector's supported `exec` source on Windows. The exec source runs `emit-security-events.ps1`, which reads Security log events with `Get-WinEvent`, emits JSON lines, and then lets Vector normalize them into Hayabusa's auth shape before publishing to NATS.

This is a validation bundle, not a production installer.
