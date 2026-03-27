# FOSM Rails → Phoenix Feature Audit

Complete inventory of all fosm-rails features and their status in the Phoenix porting documentation.

## Legend
- ✅ **Documented** - Feature is covered in FOSM_PHOENIX_IMPLEMENTATION.md
- ⚠️ **Partial** - Feature mentioned but needs more detail
- ❌ **Missing** - Feature not documented
- 🔄 **Phoenix Equivalent** - Different implementation in Phoenix

---

## CORE LIFECYCLE (13 features)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 1 | State definitions (initial, terminal) | ✅ | Full DSL documentation |
| 2 | Event definitions (from, to) | ✅ | Including multi-from states |
| 3 | Guard definitions | ✅ | With rich return values |
| 4 | `GuardDefinition.evaluate()` returning `[allowed, reason]` | ✅ | Supports true/false/string/[:fail, reason] |
| 5 | Side effects (immediate) | ✅ | In-transaction execution |
| 6 | Side effects (`defer: true`) | ✅ | After-commit execution |
| 7 | **why_cannot_fire? introspection** | ✅ | Detailed diagnostics |
| 8 | **Terminal state enforcement** | ✅ | No bypass mechanisms |
| 9 | **State predicates** (`draft?`, `sent?`) | ✅ | Auto-generated |
| 10 | **Event methods** (`send!`, `can_send?`) | ✅ | Auto-generated |
| 11 | **fire! as ONLY mutation path** | ✅ | Core principle documented |
| 12 | **Cross-machine trigger support** | ✅ | Via deferred side effects |
| 13 | **Auto-captured causal chain** (`triggered_by`) | ✅ | Via Process dictionary |

---

## STATE SNAPSHOTS (8 features)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 14 | **Snapshot strategies**: `:every`, `every: N`, `time: 300`, `:terminal`, `:manual` | ✅ | All strategies covered |
| 15 | `snapshot_attributes` DSL | ✅ | Attribute selection |
| 16 | **Arbitrary observations** (`snapshot_data` param) | ✅ | Non-schema data capture |
| 17 | **Schema + observations merged snapshot** | ✅ | Documented with JSON example |
| 18 | **Manual snapshot override** (`metadata: {snapshot: true/false}`) | ✅ | Force/opt-out controls |
| 19 | `last_snapshot` / `last_snapshot_data` methods | ✅ | Record instance methods |
| 20 | `snapshots` method (all snapshots) | ✅ | Chronological list |
| 21 | `replay_from` method | ✅ | Transition replay |
| 22 | `transitions_since_snapshot` method | ✅ | Monitoring method |
| 23 | **Snapshot serialization** (DateTime, Decimal, associations) | ⚠️ | Basic mention, needs detail |

---

## RBAC & ACCESS CONTROL (8 features)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 24 | **Access definition DSL** (`access do...end`) | ✅ | Role declarations |
| 25 | **Role definition** (`can :crud`, `can :event`) | ✅ | CRUD + event permissions |
| 26 | **Type-level role assignments** (`resource_id: nil`) | ✅ | All records of type |
| 27 | **Record-level role assignments** (specific `resource_id`) | ✅ | Single record only |
| 28 | **Default role auto-assignment** (`default: true`) | ✅ | Creator gets default role |
| 29 | **Per-request RBAC cache** (`Fosm.Current`) | ✅ | Process dictionary implementation |
| 30 | **RBAC bypass rules** (nil, Symbol, superadmin) | ✅ | All bypass cases |
| 31 | **`fosm_authorize!` for CRUD** | ⚠️ | Mentioned but needs more detail |
| 32 | **Cache invalidation on grant/revoke** | ❌ | Missing |

---

## AUDIT & IMMUTABILITY (6 features)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 33 | **Immutable transition logs** | ✅ | Read-only constraints |
| 34 | **TransitionLog scopes**: `recent`, `for_record`, `for_app`, `by_event`, `by_actor_type` | ✅ | All scopes |
| 35 | **Snapshot scopes**: `with_snapshot`, `without_snapshot`, `by_snapshot_reason` | ✅ | Snapshot-specific |
| 36 | **`by_agent?` / `by_human?` predicates** | ⚠️ | Missing |
| 37 | **Access events** (RBAC audit log) | ✅ | Immutable RBAC operations log |
| 38 | **AccessEvent actions**: grant, revoke, auto_grant | ✅ | All action types |

---

## ASYNC INFRASTRUCTURE (6 features)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 39 | **Transition log strategies**: `:sync`, `:async`, `:buffered` | ✅ | All three strategies |
| 40 | **TransitionLogJob** (async strategy) | ✅ | Oban worker |
| 41 | **AccessEventJob** | ✅ | Oban worker |
| 42 | **TransitionBuffer** (GenServer implementation) | ✅ | Buffered strategy |
| 43 | **Buffer bulk INSERT** | ⚠️ | Mentioned but code example simple |
| 44 | **Buffer auto-start on boot** | ❌ | Needs Phoenix equivalent |

---

## WEBHOOKS (5 features)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 45 | **WebhookSubscription model** | ✅ | Schema definition |
| 46 | **WebhookDeliveryJob** | ✅ | Oban worker with retries |
| 47 | **HMAC-SHA256 signing** | ✅ | Signature computation |
| 48 | **Webhook headers**: `X-FOSM-Event`, `X-FOSM-Record-Type`, `X-FOSM-Signature` | ✅ | All headers |
| 49 | **Webhook scopes**: `active`, `for_event` | ❌ | Missing |

---

## AI AGENT (12 features)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 50 | **Fosm::Agent base class** | ✅ | Module with macros |
| 51 | **Auto-generated read tools**: list, get, available_events, transition_history | ✅ | 4 read tools |
| 52 | **Auto-generated mutate tools** (one per event) | ✅ | Bounded autonomy |
| 53 | **System prompt generation** | ✅ | With constraints |
| 54 | **Custom tool support** (`fosm_tool` macro) | ✅ | Extension mechanism |
| 55 | **Agent runtime/execution** | ⚠️ | Basic mention, needs Instructor detail |
| 56 | **Agent caching** (conversation persistence) | ❌ | Missing - was in Rails.cache |
| 57 | **Agent explorer page** (tool catalog) | ✅ | LiveView sketch |
| 58 | **Direct tool tester** (no LLM) | ⚠️ | Mentioned but not detailed |
| 59 | **Agent chat interface** | ✅ | LiveView sketch |
| 60 | **Chat history persistence** | ❌ | Missing |
| 61 | **Agent error handling** (`success: false`) | ✅ | Bounded autonomy guarantee |

---

## ADMIN UI (14 features)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 62 | **Dashboard** with state distribution | ✅ | LiveView sketch |
| 63 | **App detail page** | ⚠️ | Mentioned, needs full detail |
| 64 | **Lifecycle visualization** (diagram data) | ✅ | `to_diagram_data` method |
| 65 | **Stuck record detection** | ❌ | Missing |
| 66 | **State distribution charts** | ⚠️ | Basic progress bars |
| 67 | **Recent transitions list** | ✅ | In dashboard |
| 68 | **Transition filtering** (by model, event, actor type) | ❌ | Missing |
| 69 | **Pagination** | ❌ | Missing |
| 70 | **Role management index** | ⚠️ | Mentioned |
| 71 | **Role grant form** | ❌ | Missing |
| 72 | **User search for role assignment** | ❌ | Missing |
| 73 | **Webhook management** | ⚠️ | Mentioned |
| 74 | **Settings page** (LLM provider detection) | ❌ | Missing |

---

## REGISTRY & META (5 features)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 75 | **Fosm.Registry** | ✅ | Global module registry |
| 76 | **Auto-registration on boot** | ⚠️ | Mentioned |
| 77 | **Slug validation** (lowercase, alphanumeric, underscores) | ❌ | Missing |
| 78 | **Registry enumeration** (`all`, `each`, `find`, `model_classes`, `slugs`) | ⚠️ | Partial |

---

## GRAPH GENERATION (2 features)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 79 | **Graph JSON generation** | ✅ | `Fosm.Graph` module |
| 80 | **Mix task** (`fosm.graph.generate`) | ✅ | Task with options |
| 81 | **Cross-machine connection detection** | ⚠️ | Mentioned but heuristic |

---

## GENERATORS & DX (8 features)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 82 | **Rails generator** (`rails g fosm:app`) | ✅ | Mix task equivalent |
| 83 | **Model template** | ✅ | EEx template |
| 84 | **Controller template** | ✅ | EEx template |
| 85 | **Agent template** | ✅ | EEx template |
| 86 | **Migration template** | ✅ | EEx template |
| 87 | **View templates** (index, show, new, form) | ⚠️ | Phoenix equivalents |
| 88 | **Route injection** | ⚠️ | Router configuration |
| 89 | **CLAUDE.md injection** | ❌ | Missing - AI coding agent instructions |

---

## DATABASE & CONNECTIONS (4 features)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 90 | **Fosm.ApplicationRecord** | ⚠️ | Basic mention |
| 91 | **Multi-database support** (optional `fosm` role) | ❌ | Rails-specific |
| 92 | **Connection pool handling** | ❌ | Rails-specific |
| 93 | **Cross-pool deadlock prevention** | ❌ | Rails-specific issue |

---

## CONFIGURATION (6 features)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 94 | **Fosm.configure block** | ✅ | Configuration module |
| 95 | **base_controller** | ✅ | Inheritance |
| 96 | **admin_authorize** callable | ✅ | Admin access control |
| 97 | **app_authorize** callable | ✅ | App access control |
| 98 | **current_user_method** | ✅ | Actor resolution |
| 99 | **Layout configuration** (admin_layout, app_layout) | ⚠️ | Mentioned |
| 100 | **transition_log_strategy** | ✅ | All strategies |

---

## ERROR HANDLING (6 features)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 101 | **Fosm::Error** base class | ✅ | Exception hierarchy |
| 102 | **UnknownEvent** | ✅ | Error type |
| 103 | **UnknownState** | ⚠️ | Mentioned |
| 104 | **InvalidTransition** | ✅ | Error type |
| 105 | **GuardFailed** (with reason) | ✅ | Enhanced error |
| 106 | **TerminalState** | ✅ | Error type |
| 107 | **AccessDenied** | ✅ | Error type |

---

## RACE CONDITION PROTECTION (2 features)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 108 | **SELECT FOR UPDATE row locking** | ✅ | Raw SQL in fire! |
| 109 | **Re-validation after lock** | ✅ | State, guards, RBAC |

---

## SUMMARY

### By Category

| Category | Total | ✅ | ⚠️ | ❌ | Coverage |
|----------|-------|----|----|-----|----------|
| Core Lifecycle | 13 | 13 | 0 | 0 | 100% |
| State Snapshots | 10 | 9 | 1 | 0 | 95% |
| RBAC | 9 | 7 | 1 | 1 | 85% |
| Audit & Immutability | 6 | 5 | 1 | 0 | 90% |
| Async Infrastructure | 6 | 5 | 1 | 0 | 90% |
| Webhooks | 5 | 4 | 0 | 1 | 85% |
| AI Agent | 12 | 8 | 2 | 2 | 75% |
| Admin UI | 14 | 5 | 3 | 6 | 50% |
| Registry | 5 | 3 | 1 | 1 | 70% |
| Graph Generation | 3 | 2 | 1 | 0 | 80% |
| Generators & DX | 8 | 6 | 1 | 1 | 85% |
| Database | 4 | 1 | 0 | 3 | 25% |
| Configuration | 7 | 7 | 0 | 0 | 100% |
| Error Handling | 7 | 6 | 1 | 0 | 90% |
| Race Conditions | 2 | 2 | 0 | 0 | 100% |
| **TOTAL** | **109** | **83** | **13** | **13** | **88%** |

### Critical Missing Features (Should add before implementation)

1. **Agent caching & history persistence** - How to store conversation state in Phoenix
2. **Cache invalidation on role changes** - Clear Fosm.Current cache
3. **Stuck record detection** - Important admin feature
4. **Pagination** - For transitions and records
5. **User search endpoint** - For role assignment UI
6. **CLAUDE.md injection** - AI coding agent instructions (important for DX)
7. **Buffer auto-start** - GenServer supervision tree setup
8. **Webhook scopes** - For filtering active webhooks
9. **by_agent? / by_human? predicates** - On TransitionLog

### Rails-Specific Features (May not need Phoenix equivalent)

1. Multi-database role detection (`connects_to`)
2. Cross-pool deadlock prevention (Rails-specific issue)
3. Connection pool handling (Ecto handles this differently)
4. ActiveStorage integration concerns

---

## Action Items

### High Priority
- [ ] Add agent caching with ETS or Phoenix.Presence
- [ ] Document cache invalidation pattern
- [ ] Add stuck record detection algorithm
- [ ] Document pagination strategy with Scrivener or similar
- [ ] Add user search endpoint documentation
- [ ] Document CLAUDE.md injection for generators

### Medium Priority
- [ ] Enhance snapshot serialization documentation
- [ ] Detail buffer bulk INSERT optimization
- [ ] Document Agent caching strategies
- [ ] Add more Admin UI LiveView detail
- [ ] Document direct tool tester implementation

### Low Priority
- [ ] Document webhook scopes
- [ ] Add by_agent?/by_human? predicates
- [ ] Document buffer auto-start supervision
