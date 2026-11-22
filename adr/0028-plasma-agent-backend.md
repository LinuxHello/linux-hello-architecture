---
type: adr
subject: In which language the Plasma screens reach the Agent over D-Bus, given that QML cannot do it alone
artifact: adr
status: accepted
owner: "@atterdag"
concepts: [plasma, qml, dbus, cxx-qt, qtdbus, unsafe, auth-prompt, greeter, kcm]
tags: [adr, plasma, security]
sources: ["0014-agent-bus.md", "0016-prompt-hosts.md", "0026-clients-reach-the-agent-directly.md", "0027-settings-page-calls.md", "../workspace.dsl", "https://github.com/LinuxHello/linux-hello/issues/338"]
date: 2026-11-22
---

# ADR-0028: How the Plasma screens reach the Agent

## Status

Accepted, 2026-11-22, on the maintainer's decision the same day (proposed 2026-11-22). The spike of point 1 ran first (see *Spike result*): option A needs a third module that is allowed `unsafe` code, and the maintainer allowed one, holding only the cxx-qt bridge declaration, as invariant 4 of `linux-hello`'s AGENTS.md requires. For [linux-hello#338](https://github.com/LinuxHello/linux-hello/issues/338). Not built yet.

## Context

Linux Hello's screens on KDE Plasma are written in QML, the language Plasma's screens are made of: the login screen's greeter, the part in KDE's lock screen, the notification after sign-in, and the page in System Settings. They all get their information from the Linux Hello Agent, the system service that runs the fingerprint, the face and the PIN, over its D-Bus interface `io.github.LinuxHello.Agent1`. D-Bus is the message service programs on a Linux desktop use to call each other. The settings page also sends a PIN, over the Agent's PIN socket, never over D-Bus ([ADR-0021](0021-pin-transport.md)).

QML cannot speak D-Bus by itself, and a screen may not start a program to do it ([ADR-0026](0026-clients-reach-the-agent-directly.md)). So every screen needs a small part in a compiled language that QML imports: it calls the Agent, follows its signals and hands the state to QML. The shared Auth Prompt module ([linux-hello#318](https://github.com/LinuxHello/linux-hello/issues/318)) already takes the Agent's state as one plain object; what is missing is the part that fills it. `workspace.dsl` says "Rust/cxx-qt" for the `plasma` container, but no ADR has weighed it, and building it has two consequences that need a decision first:

- **`unsafe` code.** cxx-qt is a library that lets Rust code define objects QML can use. It works through generated glue between Rust and C++. Whether that glue puts `unsafe` into Linux Hello's own crate, or only into the cxx-qt library, is not checked. If it does, the crate needs an entry in `scripts/ci/unsafe-allowlist.txt`, a third audited module next to the TPM provider's and the PAM module's (invariant 4).
- **Qt in the build.** Any option that compiles against Qt needs Qt's development files where it is built. The CI runners of `linux-hello` have none today, and the main Cargo workspace is built and tested on every pull request.

| Option | Pros | Cons |
| :-- | :-- | :-- |
| **A. Rust with cxx-qt**, as `workspace.dsl` says | The same language and the same gates as the rest (clippy, tests, cargo-deny, fuzzing); reuses `linuxhello-dbus`, the crate that holds the interface's names, so the wire words exist once; the settings page's PIN path can reuse the Agent client of `linuxhello-ctl` | Possibly a third `unsafe` module (to check); cxx-qt and cxx are new dependencies; Qt development files and CMake-free builds through `cxx-qt-build` need checking on Ubuntu 26.04 |
| B. C++ with Qt's own D-Bus classes (QtDBus), as KDE's own settings pages do | What KDE developers and packagers expect; no new Rust dependency; QtDBus is part of Qt | A second compiled language, with no memory safety and none of the repository's gates; the interface's names written a second time; the settings page would handle the PIN in C++ |
| C. Python with PySide6 | Quickest to write; the greetd spike used it | A Python runtime inside the login screen and the lock screen; slower start; a third language to package and confine |

## Decision

**Option A, Rust with cxx-qt,** with one module allowed `unsafe` code that holds only the bridge declaration (the spike showed cxx-qt needs it, and the maintainer allowed it).

1. **The spike** (half a day, in the desktop test VM): a cxx-qt object that exposes the Agent's state for one prompt to QML, built with `cxx-qt-build` against Ubuntu 26.04's Qt 6.10. It answers: does `#![forbid(unsafe_code)]` hold in Linux Hello's crate, or does the bridge need `#[allow(unsafe_code)]` there; and do cxx-qt and cxx pass `cargo deny check` with the project's licence rules.
2. **The `unsafe` module.** It is confined to one module that holds only the `#[cxx_qt::bridge]` declaration and a re-export, listed in `scripts/ci/unsafe-allowlist.txt`; the crate root sets `#![deny(unsafe_code)]`, and `scripts/ci/unsafe-policy.sh` checks the crate like the two others. Invariant 4 names it as the third audited module.
3. **Where it lives.** A crate `linuxhello-plasma` (a new crate name is a one-way door; it is decided with this ADR) in `plasma/linuxhello-plasma/`, outside the main Cargo workspace, built as a QML plugin that both Linux Hello's own greeter and KDE's lock screen can import (`io.github.LinuxHello.AgentLink`). It has a CI job of its own that builds in an Ubuntu 26.04 container with Qt and Rust from Ubuntu's archive, because the Ubuntu 24.04 runners have Qt 6.4. The main workspace's gates stay as they are and need no Qt.
4. **What it does.** One QML-facing object per prompt that the screen gives a prompt id or asks to watch (`WatchPrompts`), and that fills the Auth Prompt's state object from `Ping`, `Subscribe`, `GetState` and the signals `MethodsAvailable`, `ActiveMethods`, `State`, `Result` and `MethodEnded`. It starts no program.

## Spike result

Run on 2026-11-22 in the desktop test VM (Ubuntu 26.04, Qt 6.10.2, Rust 1.93 from Ubuntu's archive). A small crate defined one QML object, `AgentState`, with a property `reachable` and a method `ping()` that asks the real Linux Hello Agent in the VM over the system bus (`org.freedesktop.DBus.Peer.Ping`, with zbus 6.5 as the rest of the project uses it). A QML file created the object, called `ping()` and printed the property.

1. **`#![forbid(unsafe_code)]` does not hold.** With it at the crate root the build fails: cxx-qt's macro expands the bridge into `unsafe` blocks, `unsafe` functions and functions with `export_name` inside Linux Hello's crate, and the compiler points at our own lines (`#[qproperty]`, `#[qinvokable]`). cxx-qt 0.10 cannot be used without allowing `unsafe` in the crate.
2. **It can be confined to one module that holds only the declaration.** With `#![deny(unsafe_code)]` at the crate root (as the workspace sets it), a module `bridge.rs` with `#![allow(unsafe_code)]` that contains only the `#[cxx_qt::bridge]` declaration and a re-export, and the Rust behind the object in another module under `deny`, the crate builds and runs. This is the pattern of the TPM provider and the PAM module: one small module allowed `unsafe`, the rest not. cxx-qt requires the Rust type to sit directly beside the bridge (`super::T`), which the re-export satisfies.
3. **It works.** QML printed `REACHABLE true` with the Agent running and `REACHABLE false` with its unit masked (a stopped Agent is started again by D-Bus activation, so it answers).
4. **cargo-deny passes** with `linux-hello`'s own `deny.toml`: advisories, bans, licences and sources all `ok`. cxx, cxx-qt, cxx-qt-lib and cxx-qt-build are under MIT or Apache-2.0. (zbus 5 failed the advisories check on two unmaintained crates; zbus 6, which the project uses, passes.)
5. **The build** needs Qt's development packages (`qt6-base-dev`, `qt6-declarative-dev`, `qt6-base-dev-tools`) and a C++ compiler, and `QMAKE` pointing at Qt 6's `qmake`. cxx-qt-build needs no CMake.

The maintainer allowed the third module on 2026-11-22, so option A stands.

## Consequences

**Easier:** one language for everything that talks to the Agent, under the same gates; the D-Bus names exist once, in `linuxhello-dbus`; the settings page's PIN stays in Rust.

**Harder:**

- Qt's development files in a CI job of its own, and a second Cargo workspace to keep up to date.
- Possibly a third module allowed `unsafe` code, which needs the maintainer's review and an audit like the other two.
- cxx-qt is younger than QtDBus and changes between versions; the version is pinned and checked like tss-esapi and zbus.
