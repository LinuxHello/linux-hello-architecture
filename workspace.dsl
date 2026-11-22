/*
 * Linux Hello — C4 workspace (System Context, Container, Component)
 * Source notes: docs/architecture/ (Arc42 sections, README.md)
 * Status: draft, UNTESTED — validate with the Structurizr CLI before use.
 * Date: 2026-11-08 (ADR-0005 option B; ADR-0014 to 0017; spikes 0008-0012 and 0014; deployment of the Agent)
 */
workspace "Linux Hello" "Biometric- and PIN-gated passkeys and secrets for the Linux desktop" {

    model {
        user = person "Desktop user" "Signs in to the session, websites and apps; enrols methods"
        admin = person "Administrator" "Authorises a trust-chain reset"

        linuxHello = softwareSystem "Linux Hello" "PIN-rooted, biometric-unlocked credential layer integrating upstream Linux components" {

            agent = container "Linux Hello Agent" "Unlock state, auth state, routing policy, PIN, enrolment and reset orchestration" "Rust daemon, systemd system service, D-Bus on the system bus (ADR-0014)" {
                dbusApi = component "D-Bus API" "io.github.LinuxHello.Agent1 on the system bus; verifies peer credentials of every caller, keeps state per uid and sends it by method reply or unicast signal, never a broadcast that names a user or a method (ADR-0014)" "zbus"
                unlockState = component "Unlock State Manager" "Session unlock, expiry and re-prompt rules; state proven by TPM policy sessions, not flags" "Rust"
                authState = component "Auth State Publisher" "Signals MethodsAvailable, ActiveMethod, State, Result per prompt (UX1-UX4) and Closed when a prompt closes" "zbus signals"
                policyEngine = component "Routing Policy Engine" "Merges default, user and admin layers; answers allowed methods per context, provider and prompt level per relying party, PIN rules; fails closed on unparseable policy" "Rust"
                pinManager = component "PIN Manager" "Change PIN in place, PIN rules, lockout status (UX7b)" "Rust"
                enrolment = component "Enrolment Orchestrator" "First-run PIN, root key creation, second-credential prompts (UX8)" "Rust"
                methodOrch = component "Method Orchestrator" "Runs face, fingerprint and PIN in parallel for a prompt the PAM module opened; first success wins; cancels the rest (UX3); runs fingerprint and Howdy itself (ADR-0023)" "Rust, async"
                pinSocket = component "PIN Socket" "Dedicated unix stream socket of the Agent in a directory only the Agent's user can change; reads the caller's uid and pid with SO_PEERCRED and accepts the PIN only for the subject user the control call on the bus named; carries the PIN and nothing else, never as a D-Bus message body (ADR-0021)" "Rust, unix socket"
                pinVerifier = component "PIN Verifier" "Stretches the PIN (per-user salt, slow key derivation) and satisfies TPM2 auth on the root key through a salted HMAC session with parameter encryption; only the Agent talks to the TPM; the Agent's per-user counter throttles before the TPM's anti-hammering applies; every PIN buffer is zeroized (ADR-0021)" "Rust"
                faceClient = component "Face Client" "Requests a face match from Howdy" "Rust"
                fingerClient = component "Fingerprint Client" "Requests a verify from fprintd" "zbus"
                resetCoord = component "Reset Coordinator" "Destructive reset per ADR-0003 (LH-1)" "Rust"
                credStore = component "Credential Index" "Resident (discoverable) credentials, in index.json in the Agent's state directory: handle (the credential ID of a resident key) to relying party, user entity, provider and TPM-wrapped key blobs; answers a get with no allow list; no private key material (spike 0120)" "Rust"
                auditLog = component "Audit Logger" "Structured journald events for every unlock, sign, PIN change and reset" "Rust"
            }

            pamModule = container "pam_linuxhello" "Thin synchronous PAM client of the Agent: opens the prompt, waits with a hard deadline and maps the answer to a PAM code (ADR-0023)" "Rust cdylib, Linux-PAM" {
                pamEntry = component "PAM Entry Points" "pam_sm_authenticate and pam_sm_open_session" "Rust FFI"
                agentClient = component "Agent Client" "Opens the prompt and hands the conversation to the Agent's orchestrator over the system bus; connects within 250 ms and waits within the policy deadline; sends the PIN to the Agent's PIN socket, never as a D-Bus message; returns PAM_AUTHINFO_UNAVAIL when Linux Hello is unavailable and never PAM_SUCCESS for that case (P-20); starts no thread, executor or subprocess in the host process (ADR-0023)" "Rust, synchronous; its own D-Bus codec, no zbus (ADR-0023, amendment 2026-11-21)"
            }

            tpmProvider = container "TPM Credential Provider" "Device-bound passkeys under the per-user TPM root key" "Rust daemon" {
                tpmProviderApi = component "Provider Interface" "Credential operations the Virtual CTAP Authenticator calls; knows nothing about uhid, so another front end can replace it (ADR-0005)" "zbus"
                tpmKeys = component "TPM Key Service" "Root key as a non-primary child of a storage primary, PIN change in place (new blob, old blob deleted), child keys, policy sessions, signing (spike 0011)" "Rust"
                tpmFfi = component "TPM FFI" "The one module of this container allowed unsafe code; the PAM module has the other (invariant 4)" "tss-esapi"
            }

            kpxcBridge = container "KeePassXC Provider Bridge" "Portable passkeys from KeePassXC" "Rust daemon" {
                kpxcProviderApi = component "Provider Interface" "Credential operations the Virtual CTAP Authenticator calls (ADR-0005)" "zbus"
                kpxcClient = component "KeePassXC Protocol Client" "Encrypted browser-protocol channel to KeePassXC" "Rust, NaCl box"
            }

            ctapHelper = container "Virtual CTAP Authenticator" "Presents Linux Hello as a FIDO security key to browsers and apps; routes each request to a provider by policy (ADR-0005 option B)" "Rust daemon, uhid (privileged helper)"

            plasma = container "Plasma Integration" "Prompts, greeter and lock-screen integration, enrolment and settings" "Rust/cxx-qt, QML, KCM" {
                authPrompt = component "Auth Prompt QML Component" "Shared method indicator and switcher; renders Agent auth state (UX1-UX5). One QML module in the system QML directory, imported by every host below (spike 0009)" "QML"
                agentLink = component "Agent Link" "The QML plugin io.github.LinuxHello.AgentLink: follows a prompt over the Agent's D-Bus interface (Ping, WatchPrompts, Subscribe, GetState and the state signals) and hands the Auth Prompt its state; Rust with cxx-qt, one bridge module allowed unsafe code (ADR-0028)" "Rust, cxx-qt"
                lockPrompt = component "Lock Screen Prompt" "Linux Hello's shared prompt in a slot of KDE's lock screen, showing the live state of every method. Needs KDE to add the slot; until then the lock screen shows only the PAM module's text. Talks only to the Agent through the shared prompt; runs no command (ADR-0016, amendment of 2026-11-21). Not built" "QML"
                promptUi = component "Prompt UI" "In-session presence, verification and credential/provider-choice dialogs, outside the calling app. Shows the relying-party id from the request and labels from the Credential Index, never client text; confined process (own AppArmor profile, not dumpable) started by the Agent; a click is never a verification (spike 0120, ADR-0020)" "QML"
                greeter = component "Linux Hello Greeter" "Linux Hello's own login screen: the program linuxhello-greeter, run by greetd under cage. It shows every PAM question and line with its kind, lists the installed desktops from the session files and starts the chosen one through greetd. Talks to greetd's socket through the Greetd object of the Agent Link plugin, and to the Agent only to ask whether it runs; runs no command (ADR-0016, amendment of 2026-11-21; ADR-0028, amendment of 2026-11-22)" "QML, Rust"
                kcm = component "Linux Hello Settings Module" "Own settings page next to Users in System Settings (kcm_users has no extension point, spike 0010): methods, policy (UX7a)" "KCM, QML"
                faceEnrol = component "Face Enrolment Module" "Capture, recognition test and delete through Howdy; status text and the test result, no live preview in 1.0 (ADR-0015; UX6a deferred)" "QML, Rust"
                pinSettings = component "PIN Settings" "Change PIN, rules, lockout status, forgot-PIN link (UX7b)" "QML"
                wizard = component "Enrolment Wizard" "First run: PIN, then optional face and fingerprint (UX8)" "QML"
                usersKcmPatch = component "Users Page Entries" "Optional, not planned: Face and PIN entries beside fingerprint need an upstream change to kcm_users in plasma-workspace (spike 0010)" "QML patch"
            }

            cli = container "linuxhello-ctl" "Enrol, change PIN, reset, inspect" "Rust CLI" {
                cliCommands = component "Command Parser" "enrol, pin change, reset, policy show" "clap"
                cliAgentClient = component "Agent Client" "Calls the Agent D-Bus API" "zbus"
            }

            policyStore = container "User Policy" "User layer, kept by the Agent" "TOML" "Data"
            adminPolicyStore = container "Admin Policy" "Admin layer: /etc/linuxhello/policy.d/*.toml, root-owned; locked keys win" "TOML" "Data"

            secProfiles = container "Security Profiles" "Confinement and detection shipped with Linux Hello" "AppArmor, Tetragon, alert rules" {
                aaProfiles = component "AppArmor Profiles" "One enforce profile per daemon and CLI; units refuse to start unconfined" "AppArmor"
                tetraPolicies = component "Tetragon TracingPolicies" "Optional: TPM access, policy and PAM writes, ptrace, network Sigkill" "Tetragon YAML"
                alertRules = component "Alert Rules" "Alerts on Tetragon events and audit log entries" "LogQL"
            }
        }

        uhid = softwareSystem "Linux uhid and hidraw" "Kernel virtual HID device: /dev/uhid creates the FIDO device, browsers and apps reach it through hidraw" "External"
        keepassxc = softwareSystem "KeePassXC" "Password manager holding portable passkeys (GPL)" "External"
        fprintd = softwareSystem "fprintd" "Fingerprint daemon (GPL)" "External"
        howdy = softwareSystem "Howdy" "IR face recognition (MIT). Match as a subprocess (exit status); enrol and test as a root CLI; no library, D-Bus API, preview or detection results (spike 0008)" "External"
        linuxPam = softwareSystem "Linux-PAM" "Pluggable authentication framework" "External"
        tpm = softwareSystem "TPM 2.0" "Kernel resource manager /dev/tpmrm0" "External"
        camera = softwareSystem "Camera" "UVC camera with RGB and IR as separate V4L2 nodes; Howdy holds the IR stream while it captures; the BRIO streams RGB and IR together only in some start orders (spike 0012)" "External"
        secretService = softwareSystem "Secret Service (KWallet)" "Token and secret storage" "External"
        greetd = softwareSystem "greetd" "Small login service: runs PAM for the person signing in and starts the chosen desktop; the screen is a separate greeter program it talks to over a socket. SDDM and the Plasma Login Manager still work with pam_linuxhello, through PAM text only (ADR-0016, amendment of 2026-11-21)" "External"
        lockScreen = softwareSystem "kscreenlocker" "Plasma lock screen; a part of the Plasma shell package from 6.8" "External"
        systemSettings = softwareSystem "KDE System Settings" "Hosts KCMs; Users page with a fixed fingerprint entry" "External"
        browsers = softwareSystem "Browsers" "Firefox, Chromium" "External"
        nativeApps = softwareSystem "Native and Electron apps" "e.g. Claude Desktop" "External"
        relyingParties = softwareSystem "Relying parties" "Websites and identity providers" "External"
        apparmor = softwareSystem "AppArmor" "Kernel LSM, mandatory access control" "External"
        tetragon = softwareSystem "Tetragon" "eBPF runtime security (optional)" "External"
        udev = softwareSystem "udev" "Creates device files and sets who may open them. Linux Hello ships two rules: /dev/uhid for the uhid helper only (spike 0121), and each virtual key's hidraw file for the one user named in its uniq field, without the uaccess tag (71-lh-session-key.rules, ADR-0025, proposed)" "External"
        logind = softwareSystem "systemd-logind" "Tracks sessions and seats: which session is in front on a seat, and whether it is locked (LockedHint)" "External"
        journald = softwareSystem "systemd-journald" "System log" "External"
        logStack = softwareSystem "Log stack" "e.g. Alloy, Loki, Grafana" "External"
        mgmt = softwareSystem "Device management" "Future: delivers admin policy, as Intune does" "External"

        # People
        user -> greeter "Signs in, chooses a desktop"
        user -> lockScreen "Unlocks"
        user -> browsers "Signs in to websites"
        user -> nativeApps "Uses"
        user -> systemSettings "Manages sign-in methods"
        user -> promptUi "Confirms, switches method"
        user -> wizard "Enrols on first run"
        admin -> cliCommands "Authorises reset"

        # External to external (context only)
        browsers -> uhid "WebAuthn requests as CTAP2 to a USB security key" "hidraw"
        nativeApps -> uhid "WebAuthn requests as CTAP2 to a USB security key" "hidraw"
        nativeApps -> secretService "Stores tokens" "Secret Service API"
        browsers -> relyingParties "WebAuthn ceremonies" "HTTPS"
        uhid -> ctapHelper "Delivers CTAP2 reports" "/dev/uhid"
        greetd -> linuxPam "Authenticates via" "PAM"
        lockScreen -> linuxPam "Authenticates via the kde service, where pam_linuxhello runs every method; shows the module's text until KDE ships the slot, on Plasma 6.6 and 6.8 (ADR-0016, amendment of 2026-11-21, point 7)" "PAM"

        # KDE integration
        greetd -> greeter "Starts the greeter; passes each PAM question and line with its kind" "greetd IPC, unix socket"
        greeter -> greetd "Answers PAM questions, starts the chosen desktop" "greetd IPC, unix socket"
        greeter -> authPrompt "Embeds"
        lockScreen -> lockPrompt "Shows in a slot of its lock screen; needs a change in KDE" "QML"
        lockPrompt -> authPrompt "Embeds"
        promptUi -> authPrompt "Embeds"
        authPrompt -> agentLink "Reads the state of the prompt it shows"
        agentLink -> dbusApi "Watches for and subscribes to prompts, reads their state, over the system bus (ADR-0014, ADR-0028)" "D-Bus"
        systemSettings -> kcm "Hosts" "KCM"
        systemSettings -> usersKcmPatch "Shows entries on Users page"
        usersKcmPatch -> faceEnrol "Opens"
        usersKcmPatch -> pinSettings "Opens"
        kcm -> faceEnrol "Opens"
        kcm -> pinSettings "Opens"
        kcm -> dbusApi "Reads and writes settings" "D-Bus"
        kcm -> policyStore "Writes user policy" "TOML"
        wizard -> dbusApi "Starts enrolment" "D-Bus"
        wizard -> systemSettings "Hands off fingerprint enrolment to Users page"
        faceEnrol -> howdy "Enrol, test, delete through the howdy CLI in a privileged Agent helper; no preview or detection results (ADR-0015)" "subprocess"
        howdy -> camera "Reads the IR stream while it captures" "V4L2"
        pinSettings -> dbusApi "Change PIN, lockout status" "D-Bus"
        ctapHelper -> promptUi "Presence, verification and choice prompts, one per request" "D-Bus"
        promptUi -> dbusApi "Reads routing decision, authenticates" "D-Bus"

        # PAM module
        linuxPam -> pamEntry "Loads module" "PAM stack"
        pamEntry -> agentClient "Authenticate"
        agentClient -> pinSocket "Sends the PIN to the Agent, nothing else (ADR-0021)" "Unix socket, SO_PEERCRED"
        pinSocket -> methodOrch "PIN for the prompt"
        agentClient -> dbusApi "Opens the prompt and hands over the conversation; connect limit 250 ms, PAM_AUTHINFO_UNAVAIL on any failure (ADR-0023)" "D-Bus"
        dbusApi -> methodOrch "Runs the conversation for the prompt"
        methodOrch -> pinVerifier "PIN path"
        methodOrch -> faceClient "Face path"
        methodOrch -> fingerClient "Fingerprint path"
        methodOrch -> authState "Method state and result"
        pinVerifier -> tpm "TPM2 policy auth" "TCTI device"
        faceClient -> howdy "Match request; result is the exit status" "subprocess"
        fingerClient -> fprintd "Verify" "D-Bus"

        # Agent
        dbusApi -> unlockState "Unlock queries"
        dbusApi -> authState "State updates"
        dbusApi -> policyEngine "Routing queries"
        dbusApi -> pinManager "PIN requests"
        dbusApi -> enrolment "Enrol requests"
        dbusApi -> resetCoord "Reset requests"
        policyEngine -> policyStore "Reads" "TOML"
        pinManager -> tpmKeys "Change root key auth" "D-Bus"
        enrolment -> tpmKeys "Create root key" "D-Bus"
        resetCoord -> tpmKeys "Destroy root key" "D-Bus"
        resetCoord -> linuxPam "Verifies account password" "PAM conversation"
        unlockState -> auditLog "Events"
        pinManager -> auditLog "Events"
        resetCoord -> auditLog "Events"

        # Providers
        ctapHelper -> tpmProviderApi "Credential operations" "D-Bus"
        ctapHelper -> dbusApi "Checks unlock and routing policy" "D-Bus"
        tpmProviderApi -> dbusApi "Checks unlock and policy" "D-Bus"
        tpmProviderApi -> credStore "Looks up the wrapped key of a credential"
        dbusApi -> credStore "Finds a site's passkeys for a request with no allow list, and resolves the handles in an allow list (spike 0120)"
        unlockState -> logind "Follows which session is in front and whether it is locked (ADR-0025, proposed)" "D-Bus"
        unlockState -> ctapHelper "Asks it to create the virtual key for the user whose session is in front and unlocked, and to remove it on lock, switch or logout (ADR-0025, proposed)"
        udev -> ctapHelper "Applies Linux Hello's rules to the devices the helper creates: /dev/uhid for the helper only, each virtual key's hidraw file for its one owner (ADR-0025, proposed)" "udev rules"
        tpmProviderApi -> tpmKeys "Sign assertion"
        tpmKeys -> tpmFfi "ESAPI calls"
        tpmFfi -> tpm "Commands" "/dev/tpmrm0"
        ctapHelper -> kpxcProviderApi "Credential operations" "D-Bus"
        kpxcProviderApi -> dbusApi "Checks unlock and policy" "D-Bus"
        kpxcProviderApi -> kpxcClient "Get or create passkey"
        kpxcClient -> keepassxc "Browser protocol" "Unix socket"

        # Policy
        policyEngine -> adminPolicyStore "Reads; locked keys win" "TOML"
        pinManager -> policyEngine "PIN rules"
        methodOrch -> policyEngine "Allowed methods for context"
        admin -> adminPolicyStore "Writes admin policy"
        mgmt -> adminPolicyStore "Delivers admin policy (future)"

        # Confinement and monitoring
        aaProfiles -> apparmor "Loaded into (enforce)"
        apparmor -> agent "Confines"
        apparmor -> tpmProvider "Confines"
        apparmor -> kpxcBridge "Confines"
        apparmor -> ctapHelper "Confines"
        apparmor -> cli "Confines"
        tetraPolicies -> tetragon "Loaded into"
        tetragon -> logStack "Security events"
        auditLog -> journald "Audit events"
        journald -> logStack "Shipped by Alloy"
        alertRules -> logStack "Loaded into"

        # CLI
        cliCommands -> cliAgentClient "Invokes"
        cliAgentClient -> dbusApi "Calls" "D-Bus"

        # Deployment: only what runs today. The PAM module, providers and Plasma pieces have no unit yet.
        workstation = deploymentEnvironment "Workstation" {
            deploymentNode "Ubuntu workstation" "Ubuntu 24.04 or 26.04 LTS with a TPM 2.0 (tested in a VM with a software TPM)" "Linux" {
                systemd = infrastructureNode "systemd" "Starts the unit as user linuxhello with a strict sandbox; ExecStartPre refuses to start unless the AppArmor profile is loaded in enforce mode" "linuxhello-agent.service"
                apparmorLsm = infrastructureNode "AppArmor" "Profile linuxhello-agent in enforce mode: system bus socket, /dev/tpmrm0, /var/lib/linuxhello, admin policy read-only; no network, capability, ptrace or home directory" "Kernel LSM"
                systemBus = infrastructureNode "System bus" "dbus-daemon; its policy file: any user calls the Agent's interface; only the Agent's user owns the name and sends its signals" "D-Bus system bus"
                tpmDevice = infrastructureNode "TPM resource manager" "/dev/tpmrm0, the only device the unit allows" "Kernel"
                stateDir = infrastructureNode "State directory" "/var/lib/linuxhello, mode 0700" "Filesystem"
                adminPolicyDir = infrastructureNode "Admin policy" "/etc/linuxhello/policy.d, read-only for the Agent" "Filesystem"
                agentInstance = containerInstance agent
            }
        }
        systemd -> agentInstance "Starts and sandboxes" "systemd unit"
        apparmorLsm -> agentInstance "Confines (enforce)"
        agentInstance -> systemBus "Owns the Agent's bus name and serves the state API" "D-Bus, unix socket"
        agentInstance -> tpmDevice "Will open (not yet used)" "/dev/tpmrm0"
        agentInstance -> stateDir "Reads and writes" "Filesystem"
        agentInstance -> adminPolicyDir "Reads" "Filesystem"
    }

    views {
        systemContext linuxHello "Context" {
            include *
            autoLayout lr
        }
        deployment linuxHello "Workstation" "AgentDeployment" {
            include *
            autoLayout lr
        }
        container linuxHello "Containers" {
            include *
            autoLayout lr
        }
        component agent "Agent" {
            include *
            autoLayout lr
        }
        component pamModule "PAM" {
            include *
            autoLayout lr
        }
        component tpmProvider "TPMProvider" {
            include *
            autoLayout lr
        }
        component kpxcBridge "KeePassXCBridge" {
            include *
            autoLayout lr
        }
        component plasma "Plasma" {
            include *
            autoLayout lr
        }
        component cli "CLI" {
            include *
            autoLayout lr
        }
        component secProfiles "SecurityProfiles" {
            include *
            autoLayout lr
        }
        styles {
            element "Person" {
                shape person
            }
            element "External" {
                background #999999
                color #ffffff
            }
            element "Data" {
                shape cylinder
            }
        }
    }
}
