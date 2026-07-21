# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security vulnerabilities.

Instead, email **dalmia.aryan@gmail.com** with:

- A description of the vulnerability
- Steps to reproduce (or a proof of concept)
- The potential impact, if known

You can expect an acknowledgement within a few days. Please give a reasonable
window to fix the issue before any public disclosure.

## Scope

This project handles Google authentication and stores encrypted CGPA data
(encryption/decryption is performed by a Cloudflare Worker, keyed per user).
Reports touching authentication, Firestore access rules, the encryption worker,
or exposure of user data are especially valued.

Secrets (`lib/firebase_options.dart`, `.env`) are gitignored and must never be
committed. If you find a leaked credential in the git history, please report it
privately rather than filing a public issue.
