# FOSM Phoenix Porting Plan

## Phase 1: Core Foundation (Week 1-2)

### 1.1 Project Structure
```
lib/fosm/
  ├── lifecycle/
  │   ├── definition.ex       # Holds states/events/guards/side_effects/access
  │   ├── state_definition.ex
  │   ├── event_definition.ex
  │   ├── guard_definition.ex
  │   ├── side_effect_definition.ex
  │   ├── access_definition.ex
  │   ├── role_definition.ex
  │   └── snapshot_configuration.ex
  ├── lifecycle.ex            # Main DSL module (use Fosm.Lifecycle)
  ├── current.ex              # Per-process RBAC cache
  ├── transition_buffer.ex    # Buffered log strategy
  ├── registry.ex             # Global slug → model module
  ├── configuration.ex        # Runtime config
  ├── errors.ex               # Exception structs
  ├── agent.ex                # Base agent module
  └── repo.ex                 # Ecto repo wrapper

lib/fosm_web/
  ├── live/
  │   ├── admin/
  │   │   ├── dashboard_live.ex
  │   │   ├── app_detail_live.ex
  │   │   ├── roles_live.ex
  │   │   ├── transitions_live.ex
  │   │   ├── webhooks_live.ex
  │   │   └── agent/
  │   │       ├── explorer_live.ex
  │   │       └── chat_live.ex
  │   └── shared/
  ├── components/
  └── layouts/

priv/repo/migrations/
  # All FOSM migrations

priv/templates/
  # Mix generator templates
```

### 1.2 Database Schema (Ecto Migrations)

** fosm_transition_logs **
- id: bigint
- record_type: string (not null)
- record_id: string (not null)
- event_name: string (not null)
- from_state: string (not null)
- to_state: string (not null)
- actor_type: string
- actor_id: string
- actor_label: string
- metadata: jsonb (default: {})
- state_snapshot: jsonb
- snapshot_reason: string
- created_at: utc_datetime (not null)
- Indexes: record_type+record_id, event_name, created_at, actor_label

** fosm_role_assignments **
- id: bigint
- user_type: string (not null)
- user_id: string (not null)
- resource_type: string (not null)
- resource_id: string (nullable)
- role_name: string (not null)
- granted_by_type: string
- granted_by_id: string
- created_at: utc_datetime (not null)
- Unique: user_type+user_id+resource_type+resource_id+role_name

** fosm_access_events **
- id: bigint
- action: string (grant/revoke/auto_grant)
- user_type, user_id, user_label
- resource_type, resource_id
- role_name
- performed_by_type, performed_by_id, performed_by_label
- created_at

** fosm_webhook_subscriptions **
- id: bigint
- model_class_name: string
- event_name: string
- url: string
- secret_token: string (encrypted)
- active: boolean
- created_at, updated_at

### 1.3 Core DSL Module (`Fosm.Lifecycle`)

```elixir
defmodule MyApp.Invoice do
  use Ecto.Schema
  use Fosm.Lifecycle  # The main macro

  schema "invoices" do
    field :name, :string
    field :amount, :decimal
    field :state, :string  # Required - managed by FOSM
    belongs_to :created_by, MyApp.User
    timestamps()
  end

  lifecycle do
    state :draft, initial: true
    state :sent
    state :paid, terminal: true
    state :cancelled, terminal: true

    event :send_invoice, from: :draft, to: :sent
    event :pay, from: :sent, to: :paid
    event :cancel, from: [:draft, :sent], to: :cancelled

    guard :has_line_items, on: :send_invoice do
      # receives the record, returns :ok or {:error, reason}
      # pure function - no side effects
    end

    side_effect :notify_client, on: :send_invoice do
      # runs in transaction after state change
      # receives record + transition data
    end

    access do
      role :owner, default: true do
        can :crud
        can :send_invoice, :cancel
      end

      role :approver do
        can :read
        can :pay
      end
    end

    # Optional: state snapshots for time-travel debugging
    snapshot every: 10  # or :every, time: 300, :terminal, :manual
    snapshot_attributes [:amount, :due_date]
  end
end
```

### 1.4 Key Implementation Details

**State Predicates** - Auto-generated at compile time:
```elixir
# Generates:
def draft?(record), do: record.state == "draft"
def sent?(record), do: record.state == "sent"
# ... etc
```

**Event Methods** - Auto-generated at compile time:
```elixir
# Generates:
def send_invoice!(record, actor: nil, metadata: %{})
def can_send_invoice?(record)
def available_events(record)  # returns [:pay, :cancel] etc
```

**The `fire!` function** - Only mutation path:
```elixir
def fire!(record, event_name, actor: nil, metadata: %{}, snapshot_data: nil) do
  # 1. Validate event exists
  # 2. Check current state not terminal
  # 3. Check event valid from current state
  # 4. Run guards (pure functions)
  # 5. RBAC check (via cache lookup)
  # 6. Acquire row lock (SELECT FOR UPDATE via Ecto)
  # 7. Re-validate after lock
  # 8. Transaction: UPDATE state, run side effects, optional INSERT log
  # 9. Enqueue webhook delivery (async)
  # 10. Return {:ok, record} or {:error, reason}
end
```

**Transition Log Strategies**:
- `:sync` - INSERT inside transaction
- `:async` - Oban job after commit
- `:buffered` - GenServer buffer with periodic bulk INSERT

---

## Phase 2: RBAC System (Week 2-3)

### 2.1 `Fosm.Current` (Per-Process Cache)
```elixir
defmodule Fosm.Current do
  # Uses Elixir's Process dictionary or Agent for per-request cache
  # Loads ALL role assignments for actor in ONE query
  # Subsequent checks are O(1) map lookup

  def roles_for(actor, resource_type, resource_id \\ nil)
  def invalidate_for(actor)
end
```

### 2.2 Access Control Flow
```elixir
# Check if actor can fire event
if lifecycle.access_defined? do
  unless rbac_bypass?(actor) do
    unless actor_has_event_permission?(actor, event_name, record) do
      raise Fosm.AccessDenied
    end
  end
end

# Bypass rules:
# - nil actor (system/cron/migration)
# - Symbol actor (:system, :agent)
# - actor.superadmin? == true
```

### 2.3 Auto-Role Assignment
```elixir
# After record creation, if:
# - lifecycle has access block with default: true role
# - record has created_by/user/owner association
# Then auto-assign the default role to the creator
```

---

## Phase 3: Admin UI with LiveView (Week 3-4)

### 3.1 Dashboard (`/fosm/admin`)
- All FOSM apps with state distribution
- Links to role assignments

### 3.2 App Detail (`/fosm/admin/apps/:slug`)
- Lifecycle definition table
- State distribution chart (LiveChart or SVG)
- Stuck record detection
- Access control matrix (read-only view of roles)

### 3.3 Role Management (`/fosm/admin/roles`)
- Grant/revoke roles per resource
- Type-level vs record-level assignments
- Access event audit trail

### 3.4 Agent Explorer (`/fosm/admin/apps/:slug/agent`)
- Auto-generated tool catalog
- Direct tool tester (no LLM)
- System prompt display

### 3.5 Agent Chat (`/fosm/admin/apps/:slug/agent/chat`)
- Multi-turn conversation interface
- Tool call visualization
- Real-time state change display

### 3.6 Transitions & Webhooks
- Filterable transition log
- Webhook subscription management
- HMAC-SHA256 signing for webhooks

---

## Phase 4: AI Agent Integration (Week 4-5)

### 4.1 Agent Architecture
Options for Elixir:
1. **Instructor** (structured LLM outputs) - https://github.com/thmsmlr/instructor_ex
2. **LangChainElixir** - https://github.com/bradenlangc/chain
3. **Custom Tool Calling** using OpenAI/Anthropic APIs directly

### 4.2 Tool Generation
```elixir
defmodule Fosm.Agent do
  # Base module for FOSM agents

  defmacro __using__(opts) do
    # Registers model_class
    # Generates standard tools at compile time:
    # - list_{resources}
    # - get_{resource}
    # - available_events_for_{resource}
    # - transition_history_for_{resource}
    # - one per lifecycle event
  end

  # Standard tools from lifecycle definition
  def build_standard_tools(module, lifecycle) do
    # Returns list of tool definitions for LLM
  end

  def build_system_instructions(module, lifecycle, extra \\ nil) do
    # Returns system prompt with FOSM constraints
  end
end

# Usage:
defmodule MyApp.InvoiceAgent do
  use Fosm.Agent

  model_class MyApp.Fosm.Invoice
  default_model "anthropic/claude-sonnet-4-20250514"

  # Optional custom tools
  fosm_tool :find_overdue,
    description: "Find sent invoices past due date",
    inputs: %{} do
    # implementation
  end
end
```

### 4.3 Tool Schema
Each tool needs:
- Name (atom)
- Description (string for LLM)
- Input schema (JSON schema or Elixir typespec)
- Handler function (receives args, returns result)

### 4.4 Bounded Autonomy Guarantee
```elixir
# Agent can only call these actions:
# - Read tools: list, get, available_events, transition_history
# - Mutate tools: one per lifecycle event, calls fire! internally

# Invalid transitions return {:error, reason}
# The agent cannot bypass guards, RBAC, or terminal states
```

---

## Phase 5: Background Jobs & Webhooks (Week 5)

### 5.1 Oban Jobs
```elixir
defmodule Fosm.Jobs.TransitionLogJob do
  use Oban.Worker
  # Writes transition log for :async strategy
end

defmodule Fosm.Jobs.WebhookDeliveryJob do
  use Oban.Worker
  # HTTP POST with HMAC-SHA256 signing
  # Retry logic via Oban
end

defmodule Fosm.Jobs.AccessEventJob do
  use Oban.Worker
  # Async RBAC audit log write
end
```

### 5.2 Transition Buffer GenServer
```elixir
defmodule Fosm.TransitionBuffer do
  use GenServer
  # In-memory queue for :buffered strategy
  # Periodic flush (every ~1s) with bulk INSERT
  # Survives crashes? No - data loss acceptable for throughput
end
```

### 5.3 Webhook Payload
```elixir
%{
  event: "send_invoice",
  record_type: "Fosm.Invoice",
  record_id: "42",
  from_state: "draft",
  to_state: "sent",
  actor: %{type: "User", id: "1", label: "user@example.com"},
  metadata: %{},
  timestamp: "2026-03-27T..."
}
# Headers:
# X-FOSM-Event: send_invoice
# X-FOSM-Record-Type: Fosm.Invoice
# X-FOSM-Signature: sha256=HMAC
```

---

## Phase 6: Generators & Mix Tasks (Week 5-6)

### 6.1 Mix Generator
```bash
mix fosm.gen.app Invoice \
  --fields name:string amount:decimal client_name:string \
  --states draft,sent,paid,cancelled \
  --access authenticate_user!
```

### 6.2 Generated Files
```
lib/my_app/fosm/
  ├── invoice.ex              # Schema + lifecycle stub
  └── invoice_agent.ex        # AI agent stub

lib/my_app_web/
  ├── controllers/
  │   └── fosm/invoice_controller.ex
  ├── live/
  │   └── fosm/invoice_live.ex  # (optional LiveView CRUD)
  └── components/
      └── fosm/invoice_components.ex

priv/repo/migrations/
  └── 20240327_create_fosm_invoices.ex

config/
  └── fosm_routes.ex          # Or inject into router
```

### 6.3 Template Content
See `priv/templates/` in Rails version for structure.
Key templates:
- model.ex.eex
- controller.ex.eex
- agent.ex.eex
- migration.ex.eex
- views/*.html.heex.eex

---

## Phase 7: Configuration & Integration (Week 6)

### 7.1 Application Config
```elixir
# config/config.exs
config :fosm, Fosm.Configuration,
  base_controller: MyAppWeb.BaseController,
  admin_authorize: &MyAppWeb.FosmAuth.admin_authorize/1,
  app_authorize: &MyAppWeb.FosmAuth.app_authorize/2,
  current_user_method: &MyAppWeb.FosmAuth.current_user/1,
  admin_layout: {MyAppWeb.Layouts, :admin},
  app_layout: {MyAppWeb.Layouts, :app},
  transition_log_strategy: :async  # :sync, :async, :buffered

# Runtime config via Fosm.configure/1
```

### 7.2 Router Integration
```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  # FOSM routes
  scope "/fosm", FosmWeb do
    pipe_through :browser
    pipe_through :fosm_admin_auth

    live "/admin", Admin.DashboardLive
    live "/admin/apps/:slug", Admin.AppDetailLive
    live "/admin/roles", Admin.RolesLive
    live "/admin/apps/:slug/agent", Admin.Agent.ExplorerLive
    live "/admin/apps/:slug/agent/chat", Admin.Agent.ChatLive
    # ... etc
  end

  # Generated app routes (from mix task)
  scope "/fosm/apps", MyAppWeb.Fosm do
    pipe_through :browser
    pipe_through :authenticate_user

    resources "/invoices", InvoiceController
  end
end
```

### 7.3 Ecto Repo Integration
```elixir
defmodule Fosm.ApplicationRecord do
  use Ecto.Schema
  # Shared behavior for all FOSM models
  # Connection handling (similar to Rails' db role logic)
end
```

---

## Phase 8: Testing & Documentation (Ongoing)

### 8.1 Test Patterns
```elixir
defmodule MyApp.Fosm.InvoiceTest do
  use MyApp.DataCase
  alias MyApp.Fosm.Invoice

  test "draft invoice can be sent" do
    invoice = insert!(:invoice, state: "draft", amount: 100)
    assert Invoice.can_send_invoice?(invoice)
    assert {:ok, sent} = Invoice.send_invoice!(invoice, actor: :test)
    assert sent.state == "sent"
  end

  test "cannot pay draft directly" do
    invoice = insert!(:invoice, state: "draft")
    assert {:error, %Fosm.InvalidTransition{}} = Invoice.fire!(invoice, :pay)
  end

  test "terminal state blocks transitions" do
    invoice = insert!(:invoice, state: "paid")
    assert {:error, %Fosm.TerminalState{}} = Invoice.fire!(invoice, :cancel)
  end

  test "every transition is logged" do
    invoice = insert!(:invoice, state: "draft")
    {:ok, _} = Invoice.send_invoice!(invoice, actor: :test)

    log = Fosm.TransitionLog.for_record("MyApp.Fosm.Invoice", invoice.id) |> last()
    assert log.event_name == "send_invoice"
    assert log.from_state == "draft"
    assert log.to_state == "sent"
  end
end
```

### 8.2 Documentation
- README with installation
- AGENTS.md for AI coding agents
- LiveView storybook for components
- Full API docs via ExDoc

---

## Key Differences: Rails vs Phoenix

| Aspect | Rails | Phoenix |
|--------|-------|---------|
| **State Machine** | Runtime DSL with class_attribute | Compile-time macros with `__using__` |
| **Async Jobs** | ActiveJob/SolidQueue | Oban (PostgreSQL-backed) |
| **Caching** | CurrentAttributes | Process dictionary / ETS |
| **Admin UI** | ERB views + controllers | LiveView (much better UX) |
| **Real-time** | Turbo/ActionCable | Built-in PubSub + LiveView |
| **Background** | Separate worker processes | BEAM processes (no separation needed) |
| **Connection Pool** | Role-based multi-pool | Ecto sandboxes / dynamic repos |
| **Type Safety** | Runtime | Compile-time + Dialyzer |

### Phoenix Advantages
1. **LiveView** - Admin UI can be truly interactive without JS frameworks
2. **PubSub** - Built-in for real-time transition updates
3. **Oban** - More reliable than ActiveJob (PostgreSQL-backed, retries built-in)
4. **BEAM** - The transition buffer GenServer is simpler than Rails' threading
5. **Compile-time macros** - DSL validation at compile time, not runtime
6. **State agents** - Can use `Agent` for per-request RBAC cache

### Rails Advantages (what we lose)
1. **Gemlings** - Need to rebuild or integrate with Instructor/LangChain
2. **Mature ecosystem** - Some edge cases already solved
3. **ActiveStorage integration** - Need Phoenix equivalent

---

## Implementation Order Recommendation

1. **Week 1**: Core lifecycle DSL + basic fire! implementation
2. **Week 2**: Ecto schemas + migrations + transition log
3. **Week 3**: RBAC + Fosm.Current cache
4. **Week 4**: Oban jobs + webhooks
5. **Week 5**: LiveView admin UI (dashboard, apps, transitions)
6. **Week 6**: AI agent integration + mix generators
7. **Week 7**: Documentation + polish

Total: ~7 weeks for feature parity with Rails version
