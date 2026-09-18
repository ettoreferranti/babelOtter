# babelOtter — Architecture

Status: **proposed, awaiting approval**. Companion to
[`superpowers/specs/2026-09-18-babelotter-design.md`](superpowers/specs/2026-09-18-babelotter-design.md).

---

## 1. Trust boundary

Everything inside the dashed boundary is on your machine. The single crossing
is made by the Ollama daemon, on your explicit confirmation, and carries only a
model name — never user content.

```mermaid
flowchart TB
    subgraph MACHINE["🖥️  Your Mac — NFR-P1 boundary: no user content crosses this line"]
        direction TB

        subgraph APPS["Any macOS application"]
            SRC["Mail · Safari · Teams · Word<br/>your selected text"]
        end

        subgraph BO["babelOtter.app"]
            SHELL["BabelOtterApp<br/><i>AppKit/SwiftUI shell</i>"]
            KIT["BabelOtterKit<br/><i>pure Swift core</i>"]
            EVAL["babelotter-eval<br/><i>CLI</i>"]
        end

        subgraph STORE["~/Library/Application Support/ch.babelotter"]
            DB[("history.sqlite<br/>0600 · no iCloud · no backup")]
            CFG[("config · profiles · glossary")]
        end

        OLLAMA["Ollama daemon<br/>127.0.0.1:11434"]
        MODELS[("local model weights")]
    end

    CLOUD["ollama.com<br/>model registry"]

    SRC <-->|"Accessibility API<br/>clipboard fallback"| SHELL
    SHELL <--> KIT
    EVAL --> KIT
    KIT <-->|"HTTP · loopback only<br/>streaming NDJSON"| OLLAMA
    KIT <--> DB
    KIT <--> CFG
    OLLAMA <--> MODELS
    OLLAMA -.->|"model bytes only<br/>on explicit confirmation<br/><b>daemon opens this, not babelOtter</b>"| CLOUD

    style MACHINE stroke-dasharray: 8 6,stroke-width:3px
    style CLOUD stroke-dasharray: 4 4
    style KIT stroke-width:3px
```

**The key property:** babelOtter never opens a non-loopback socket. When a model
is missing it calls `POST 127.0.0.1:11434/api/pull`; the *daemon* performs the
download. The "exactly one networking call site, loopback-enforced" invariant
therefore holds with no exceptions, and is asserted by an architecture test.

---

## 2. Component architecture

```mermaid
flowchart TB
    subgraph SHELL["BabelOtterApp — thin OS-integration shell (excluded from mutation testing)"]
        direction LR
        MB["MenuBarController"]
        HK["HotkeyManager<br/><i>RegisterEventHotKey</i>"]
        SEL["SelectionService<br/><i>AX → clipboard fallback</i>"]
        POP["PopupPanelController<br/><i>non-activating NSPanel</i>"]
        WIN["Onboarding · Settings<br/>History · Privacy panel"]
        PERM["PermissionsService"]
        LIFE["OllamaLifecycle"]
    end

    subgraph KIT["BabelOtterKit — pure Swift, zero AppKit, ≥80% mutation score"]
        direction TB
        PIPE["<b>ActionPipeline</b><br/><i>orchestrates every action</i>"]

        subgraph TEXT["Text processing"]
            DET["LanguageDetector"]
            STR["StructureExtractor"]
            TOK["TokenProtector"]
            LOC["LocaleRules<br/><i>de-CH: ß → ss</i>"]
            DIF["WordDiffer"]
        end

        subgraph LLM["LLM access"]
            PB["PromptBuilder"]
            GW(["LLMGateway<br/><i>protocol</i>"])
            OC["OllamaClient"]
            EP["OllamaEndpoint<br/><i>loopback-enforced</i>"]
            RP["ResponseParser"]
        end

        subgraph DATA["Configuration & data"]
            CS["ConfigStore"]
            AP["AudienceProfile"]
            GL["Glossary + DNT list"]
            LP["LanguagePolicy"]
            HR(["HistoryRepository<br/><i>protocol</i>"])
            SQ["SQLiteHistoryStore"]
        end
    end

    EVALCLI["babelotter-eval"]

    HK --> PIPE
    MB --> PIPE
    SEL --> PIPE
    PIPE --> POP
    PIPE --> SEL
    LIFE --> GW
    PERM --> WIN

    PIPE --> DET & STR & TOK & PB & RP & LOC & DIF
    PIPE --> LP & CS & HR
    PB --> GW
    GW -.implemented by.-> OC
    OC --> EP
    HR -.implemented by.-> SQ
    CS --> AP & GL
    EVALCLI --> PIPE

    style PIPE stroke-width:3px
    style GW stroke-dasharray: 5 5
    style HR stroke-dasharray: 5 5
    style EP stroke-width:3px
```

Protocol seams (`LLMGateway`, `HistoryRepository`, and the detector) are what
let the core be tested without Ollama, a database, or a running macOS UI.

---

## 3. Request flow — the Translate action

```mermaid
sequenceDiagram
    autonumber
    actor U as You
    participant APP as Source app
    participant SH as Shell<br/>(Hotkey + Selection)
    participant PL as ActionPipeline
    participant OL as Ollama<br/>127.0.0.1
    participant PU as Popup
    participant DB as History

    U->>APP: select text
    U->>SH: ⌥⌘T
    SH->>APP: read AXSelectedText
    APP-->>SH: text + AXUIElement + PID
    Note over SH,APP: if AX unsupported → save clipboard,<br/>⌘C, read, restore  (v1 accepted risk)

    SH->>PL: Selection
    PL->>PL: detect language (confidence floor)
    PL->>PL: resolve target from enabled pairs
    PL->>PL: extract paragraph skeleton → blocks
    PL->>PL: mask do-not-translate → ⟦DNT0⟧
    PL->>PL: build prompt<br/>(profile · glossary · style note · schema)

    PL->>PU: show, streaming
    PL->>OL: POST /api/chat  stream:true

    loop NDJSON deltas
        OL-->>PL: token
        PL-->>PU: append (raw preview)
    end

    OL-->>PL: done
    PL->>PL: parse JSON (tolerant)
    alt block count mismatch
        PL->>OL: one retry, whole-text mode
    end
    PL->>PL: restore sentinels → reapply skeleton → LocaleRules
    PL->>PU: final text · detected audience · Replace enabled

    U->>PU: Replace
    PU->>SH: apply
    SH->>APP: reactivate, then AX set / ⌘V
    PL->>DB: record
```

Note step ordering after generation: sentinel restoration **precedes** locale
rules, and locale rules must not rewrite restored do-not-translate tokens. Both
are explicit invariants with dedicated tests — and prime mutation targets.

---

## 4. Post-processing chain

```mermaid
flowchart LR
    RAW["raw model output"] --> FENCE["strip code fences"]
    FENCE --> JSON["locate outermost<br/>JSON object"]
    JSON --> DEC{"decode ok?"}
    DEC -->|no| DEGRADE["degrade:<br/>translate → use raw<br/>correct → surface error"]
    DEC -->|yes| COUNT{"block count<br/>matches?"}
    COUNT -->|no| RETRY["retry once,<br/>whole-text mode"]
    COUNT -->|yes| UNMASK["restore ⟦DNT⟧ sentinels"]
    UNMASK --> SKEL["re-apply paragraph skeleton"]
    SKEL --> RULES["LocaleRules<br/>ß → ss, skipping DNT spans"]
    RULES --> DIFF{"action == correct?"}
    DIFF -->|yes| WD["WordDiffer → inline diff"]
    DIFF -->|no| OUT["final result"]
    WD --> OUT

    style UNMASK stroke-width:3px
    style RULES stroke-width:3px
```

---

## 5. Testing topology

```mermaid
flowchart TB
    subgraph CI["GitHub Actions · macos runner"]
        B["swift build"] --> U["unit tests<br/><i>pure, no I/O</i>"]
        U --> C["contract tests<br/><i>recorded NDJSON fixtures</i>"]
        C --> A["architecture guards<br/><i>networking call-site allowlist</i><br/><i>dependency allowlist</i>"]
        A --> M["muter on BabelOtterKit<br/><b>gate: ≥80%</b>"]
        M --> F["fixture content guard<br/><i>synthetic data only</i>"]
    end

    subgraph LOCAL["Local only — never in CI"]
        I["integration tests<br/><i>real Ollama</i>"]
        E["babelotter-eval<br/><i>model scorecards</i>"]
        S["manual UI smoke checklist"]
    end

    style M stroke-width:3px
    style LOCAL stroke-dasharray: 8 6
```

Integration and eval runs stay local for two reasons: CI runners have no models,
and no real text may ever execute on a third-party runner from a public repo.

---

## 6. Decisions and their rationale

| Decision | Why | Cost accepted |
|---|---|---|
| Pure core + thin shell | Makes logic testable and privacy invariants provable | Protocol boilerplate at the seam |
| One process, no daemon/XPC | Single-user tool; IPC is unjustified complexity | No cross-restart persistence of in-flight work |
| `RegisterEventHotKey` | Avoids the Input Monitoring permission entirely | Carbon-era API |
| Non-activating `NSPanel` | Source app keeps focus, selection survives | Fiddly positioning and key handling |
| Block-array responses | Structure mismatch becomes detectable, not silent corruption | Stricter prompt, retry path needed |
| Stream raw, post-process at end | Feels fast while staying correct | Replace stays disabled until finalised |
| Delegate model pulls to Ollama | Preserves loopback-only invariant | Depends on daemon being reachable |
| Mutation gate on core only | UI-glue mutants are noise | Shell correctness rests on manual smoke tests |

### Known risks

1. **Focus loss.** Showing the popup can deactivate the source app and drop the
   selection. Mitigated by capturing the `AXUIElement` and PID at trigger time
   and using a non-activating panel. **De-risking spike in M0** — this is the
   most likely thing to make the app feel broken.
2. **`muter` maturity.** May not run cleanly on Swift 6.4 / macOS 27.
   **Spike in M0.** Fallback: a SwiftSyntax-based in-house harness. Last resort:
   report-only — which would be reported, not quietly adopted.
3. **Sentinel fidelity.** Models may mangle `⟦DNT0⟧` markers. Needs empirical
   validation across candidate models via the eval harness.
4. **Clipboard fallback vs Universal Clipboard.** Knowingly accepted for v1;
   see [`../PRIVACY.md`](../PRIVACY.md).
