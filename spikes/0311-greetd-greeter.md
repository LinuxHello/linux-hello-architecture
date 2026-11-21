---
type: spike
subject: Can Linux Hello's own login screen be a QML greeter for greetd that starts Plasma and any other desktop?
artifact: spike
status: open
owner: "@atterdag"
concepts: [greetd, greeter, login-screen, pam, pam-linuxhello, plasma, wayland]
tags: [spike, plasma, ux]
sources: ["../notes/ui-proposals-2026-11.md", "https://github.com/LinuxHello/linux-hello/issues/311", "../adr/0016-prompt-hosts.md", "../adr/0023-pam-module-and-login-failure.md", "../adr/0024-agent-status-interface.md", "https://man.archlinux.org/man/greetd-ipc.7.en"]
date: 2026-11-21
issue: https://github.com/LinuxHello/linux-hello/issues/311
---

# Spike 0311: a Linux Hello greeter for greetd

This spike has not run yet; it is tracked in [linux-hello#311](https://github.com/LinuxHello/linux-hello/issues/311).

## Question

Linux Hello wants a login screen that shows exactly what its PAM module says: the module's own question, its messages, and whether a message is an error or only information. PAM (Pluggable Authentication Modules) is the Linux system through which a login screen asks a module to check a person; `pam_linuxhello` is Linux Hello's module, which hands the checking to the Agent, Linux Hello's system service. SDDM, the login screen Plasma uses today, cannot do this: it answers the module's question itself with the typed text and treats every error line as a failed login ([the UI proposals](../notes/ui-proposals-2026-11.md) explain what was found in its source). The maintainer therefore chose, on 2026-11-21, to build Linux Hello's own login screen (login proposal D).

The plan is not to write a whole login manager but only the screen. greetd is a small login service that runs PAM and starts the chosen desktop; the screen it shows is a separate program, the *greeter*, which talks to greetd over a socket. greetd passes each PAM question to the greeter with its text and its kind (a visible or secret question, an info line or an error line) and waits for the answer, according to its manual page `greetd-ipc(7)`.

The question, to be answered yes or no: **can a QML greeter under greetd, on Ubuntu, sign a person in with `pam_linuxhello` to Plasma on Wayland and to one other desktop, and show every question and message of the module with its kind?**

The answer decides whether the login screen is built this way, or whether Linux Hello falls back to its own SDDM theme (login proposal B).

## Time box

Two working days.

## Method

Not run yet. All steps are untested.

1. In the test VM (Ubuntu 26.04, Plasma 6.6), install greetd from the distribution and a small Wayland compositor to show the greeter (for example `cage`, which shows one program full screen). Record the versions.
2. Write a minimal greeter in QML with a small Rust or C++ part that speaks greetd's protocol: `create_session`, `post_auth_message_response`, `start_session`, `cancel_session`. It shows the text of each question above a field, and info and error lines in two colours. It must start no other program and run no command (the maintainer's rule in the UI proposals).
3. Give greetd a PAM file with Linux Hello's shipped `login` lines (`pam_linuxhello.so context=login`, then `pam_unix`).
4. Read the installed desktops from `/usr/share/wayland-sessions` and `/usr/share/xsessions` and start the chosen one's command with `start_session`.
5. Check each of the nine states drawn in login proposal D: the question, a PIN that works, a wrong PIN, an empty Enter with the fingerprint (a virtual or real sensor), a lockout, the Agent stopped (the account password must then work), and a condition such as `tpm-cleared` shown as an error before anything is typed.
6. Check what a login screen must do beyond signing in, and note each one as done, missing or out of scope: choosing the keyboard layout, the on-screen keyboard and screen reader, the user list, shutdown and restart, a second monitor, and starting after a crash.

## What a yes or no changes

- **Yes:** point 1 of the [ADR-0016](../adr/0016-prompt-hosts.md) amendment of 2026-11-21 holds: Linux Hello's login screen is a greetd greeter, in place of decision 3 (the own SDDM theme). `workspace.dsl` already models the `Linux Hello Greeter` under greetd, and the login sequence in section 6 is rewritten.
- **No or partly:** decision 3 of ADR-0016 stands, `workspace.dsl` goes back to an `SDDM Theme` component, with login proposal B, the live method row in an own SDDM theme, and the spike's findings say what greetd would need.

## Evidence

None yet.

## Answer

Open.
