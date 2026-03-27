# FOSM Phoenix

[![Hex.pm](https://img.shields.io/hexpm/v/fosm.svg)](https://hex.pm/packages/fosm)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/fosm)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> **Finite Object State Machine** for Phoenix — A declarative, auditable, multi-tenant state machine engine with RBAC, side effects, webhooks, and AI agents.

## Overview

FOSM Phoenix brings the power of finite state machines to Elixir and Phoenix, providing:

- 🔄 **Declarative Lifecycle DSL** — Define states, events, guards, and side effects
- 🔒 **RBAC with Roles** — Role-based access control with auto-assignment
- 🎩 **Side Effects** — Async, sync, and scheduled effects
- 📊 **Audit Trails** — Complete transition logging with snapshots
- 🌐 **Webhooks** — HMAC-signed webhook delivery
- 🤖 **AI Agents** — LLM-powered agents with bounded autonomy
- 📱 **Admin UI** — Phoenix LiveView admin interface
- 🔍 **Introspection** — Query available events and state history

## Quick Start

Add FOSM to your `mix.exs`:

```elixir
defp deps do
  [
    {:fosm, "~> 0.1.0"}
  ]
end
```

Create your first state machine:

```elixir
defmodule MyApp.Invoice do
  use Ecto.Schema
  use Fosm.Lifecycle

  schema "invoices" do
    field :state, :string, default: "draft"
    field :amount, :decimal
    timestamps()
  end

  lifecycle do
    state :draft, initial: true
    state :sent
    state :paid, terminal: true

    event :send do
      transition from: :draft, to: :sent
      guard :has_email do
        if record.customer_email, do: :ok, else: {:error, "Email required"}
      end
    end

    event :pay do
      transition from: :sent, to: :paid
      side_effect :send_receipt do
        MyApp.Emails.receipt(record) |> Oban.insert()
      end
    end
  end
end
```

Use it:

```elixir
# Fire events
{:ok, invoice} = MyApp.Invoice.fire!(invoice, :send, actor: current_user)
{:ok, invoice} = MyApp.Invoice.fire!(invoice, :pay, actor: current_user)

# Query available events
events = MyApp.Invoice.available_events(invoice)
# => [] (empty because 'paid' is terminal)
```

## Installation

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
mix git_hooks.setup  # Optional: Install pre-commit and pre-push hooks
```

## Documentation

- [Getting Started](guides/getting_started.md) — Setup and first steps
- [Code Quality](guides/code_quality.md) — Credo, Dialyzer, and best practices
- [API Documentation](https://hexdocs.pm/fosm) — Full API reference
- [Implementation Details](FOSM_PHOENIX_IMPLEMENTATION.md) — Architecture and internals
- [Complete Specification](FOSM_PHOENIX_COMPLETE_SPEC.md) — Feature specification

## Examples

See the [examples/](examples/) directory:

- [Invoice Workflow](examples/invoice_workflow.ex) — Complete workflow with guards, side effects, and access control

## Features

### Lifecycle Definition

```elixir
lifecycle do
  # States
  state :draft, initial: true
  state :active
  state :archived, terminal: true

  # Events with transitions
  event :activate do
    transition from: :draft, to: :active
  end

  # Guards
  guard :valid_data do
    if valid?(record), do: :ok, else: {:error, "Invalid data"}
  end

  # Side effects
  side_effect :notify do
    Notification.send(record)
  end
end
```

### Access Control

```elixir
access do
  role :admin, default: true do
    can :manage
  end

  role :editor do
    can :read, :update
    can :activate
  end
end
```

### Webhooks

```elixir
webhook :notify_payment,
  url: "https://api.example.com/webhooks",
  on: [:pay],
  secret: fn -> System.get_env("WEBHOOK_SECRET") end
```

### AI Agent

```elixir
defmodule MyApp.InvoiceAgent do
  use Fosm.Agent, model_class: MyApp.Invoice
end

# Run the agent
{:ok, response} = MyApp.InvoiceAgent.run(
  "List all draft invoices over $100",
  session_id: "sess_123"
)
```

## Quality Standards

FOSM Phoenix maintains high code quality standards:

- ✅ **Credo** — Static analysis in strict mode
- ✅ **Dialyzer** — Type checking with no errors
- ✅ **Formatter** — Consistent style enforced
- ✅ **Git Hooks** — Pre-commit and pre-push validation
- ✅ **Documentation** — All public functions documented with examples
- ✅ **Type Specs** — Complete @spec coverage
- ✅ **No Warnings** — Compiler warnings treated as errors

Run quality checks:

```bash
mix quality      # Run all quality checks
mix quality.fix  # Auto-fix formatting and run credo
mix test         # Run test suite
mix dialyzer     # Run type analysis
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Run quality checks (`mix quality`)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

Please ensure:
- All tests pass
- Credo strict mode passes
- Dialyzer has no errors
- Documentation is updated

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

FOSM Phoenix is a port of [fosm-rails](https://github.com/dwarvesfoundation/fosm) from Ruby on Rails to Elixir/Phoenix.
