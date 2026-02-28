---
title: "GPG on GNU/Linux"
description: "Understand everything about GPG on GNU/Linux os."
draft: false
date: 2026-02-20
tags: [ "linux", "security", "gpg", "asimmetrhic", "keys" ]
summary: "Understand eberything about GPG."
---

## GPG on Linux: Encrypt, Sign, and Verify
### Introduction
GPG lets you encrypt files, sign documents and code, verify software integrity, and communicate securely. It's been around since 1999 and it's used by everyone from kernel developers to journalists to system administrators.

### How GPG Works: The Theory
GPG is built on asymmetric (public-key) cryptography. Unlike symmetric encryption where the same password encrypts and decrypts, asymmetric cryptography uses a key pair:
Public key — you share this openly. Anyone can use it to encrypt messages to you or to verify your signatures.
Private key — you keep this secret. It's the only key that can decrypt messages encrypted with your public key, or create signatures that match your public key.
The mathematical relationship between the two keys ensures that deriving the private key from the public key is computationally infeasible — even with enormous computing power.

### Symmetric Encryption: GPG Does That Too
GPG also supports symmetric encryption, where a single passphrase is used to both encrypt and decrypt. This is simpler and faster, and it's useful when you're encrypting something for yourself (like a backup) and don't need the complexity of key pairs.
Under the hood, GPG uses the passphrase to derive an encryption key (using a Key Derivation Function), then encrypts the data with a strong cipher like AES-256.

#### What is AES-256

[To be continued...]
