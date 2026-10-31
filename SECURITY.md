# Security Policy

CrossLink moves clipboard contents and files between devices, so security reports are taken
seriously.

## Reporting a vulnerability

Please **do not open a public issue** for a vulnerability. Report it privately through
[GitHub Security Advisories](https://github.com/WayupKG/CrossLink/security/advisories/new)
("Report a vulnerability" on the Security tab).

Include what you can of:

- the affected component (macOS app, Android app, or the protocol itself);
- steps to reproduce or a proof of concept;
- the impact you expect (for example, reading traffic, impersonating a paired device, writing files).

You will get an answer within a week. Once a fix is released, the report is credited unless you
prefer to stay anonymous.

## Scope

The threat model is described in [PROTOCOL.md](PROTOCOL.md#security-and-limitations). In short:

- In scope: anything that lets a device on the same network read, alter, replay or inject
  CrossLink traffic, connect without the pairing secret, disconnect the paired phone, or write
  files outside the intended folders.
- Out of scope: attacks that require the QR code or pairing secret, an unlocked paired device, or
  port `48321` exposed to the Internet.

## Supported versions

Only the latest commit on `main` receives security fixes while CrossLink is below 1.0.
