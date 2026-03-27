# Getting Started with FOSM Phoenix

A complete guide to setting up and using FOSM Phoenix in your project.

## Installation

Add FOSM Phoenix to your `mix.exs`:

```elixir
defp deps do
  [
    {:fosm, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Database Setup

FOSM requires Ecto and PostgreSQL. Add the configuration:

```elixir
# config/config.exs
config :fosm, Fosm.Repo,
  database: "your_app_fosm",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"
```

Run the migrations:

```bash
mix ecto.create
mix ecto.migrate
```

## Your First FOSM Model

Create an invoice model with state machine behavior:

```elixir
defmodule MyApp.Invoice do
  use Ecto.Schema
  use Fosm.Lifecycle

  schema "invoices" do
    field :state, :string, default: "draft"
    field :amount, :decimal
    field :customer_email, :string
    timestamps()
  end

  lifecycle do
    # Define states
    state :draft, initial: true
    state :sent
    state :paid, terminal: true
    state :cancelled, terminal: true

    # Define events and transitions
    event :send do
      transition from: :draft, to: :sent
    end

    event :pay do
      transition from: :sent, to: :paid
    end

    event :cancel do
      transition from: [:draft, :sent], to: :cancelled
    end
  end
end
```

## Using the State Machine

### Firing Events

```elixir
# Create an invoice
invoice = %MyApp.Invoice{amount: Decimal.new("100.00")}
|> MyApp.Repo.insert!()

# Send it (draft -> sent)
{:ok, invoice} = MyApp.Invoice.fire!(invoice, :send, actor: current_user)

# Pay it (sent -> paid)
{:ok, invoice} = MyApp.Invoice.fire!(invoice, :pay, actor: current_user)

# Check state
invoice.state  # "paid"
```

### Checking Available Events

```elixir
# Get available events for current state
events = MyApp.Invoice.available_events(invoice)
# => [:cancel] when in draft state
# => [:pay, :cancel] when in sent state
# => [] when in terminal state
```

### Checking if Event Can Fire

```elixir
if MyApp.Invoice.can_fire?(invoice, :pay) do
  # Show pay button
end
```

## Adding Guards

Guards validate conditions before transitions:

```elixir
defmodule MyApp.Invoice do
  # ... schema ...

  lifecycle do
    # ... states ...

    event :pay do
      transition from: :sent, to: :paid

      guard :amount_positive do
        # Guard passes if this returns :ok
        # Fails if it returns {:error, reason}
        if record.amount > 0 do
          :ok
        else
          {:error, "Amount must be positive"}
        end
      end
    end
  end
end
```

## Adding Side Effects

Side effects run after successful transitions:

```elixir
defmodule MyApp.Invoice do
  # ... schema ...

  lifecycle do
    # ... states and events ...

    event :send do
      transition from: :draft, to: :sent

      side_effect :send_email do
        # Send email asynchronously via Oban
        MyApp.Emails.invoice_sent(record)
        |> Oban.insert()
      end
    end
  end
end
```

## Adding Access Control

Control who can fire events:

```elixir
defmodule MyApp.Invoice do
  # ... schema ...

  lifecycle do
    # ... states and events ...

    access do
      # Owner can do everything
      role :owner, default: true do
        can :crud
        can :send, :pay, :cancel
      end

      # Accounting can pay invoices
      role :accounting do
        can :read
        can :pay
      end

      # Support can view and cancel
      role :support do
        can :read
        can :cancel
      end
    end
  end
end
```

Assign roles:

```elixir
# Assign owner role
Fosm.assign_role(current_user, invoice, :owner)

# Check access (used automatically by fire!)
Fosm.can?(current_user, invoice, :pay)
```

## Webhooks

Notify external systems on transitions:

```elixir
defmodule MyApp.Invoice do
  # ... schema ...

  lifecycle do
    webhook :notify_payment,
      url: "https://api.example.com/webhooks/payment",
      secret: fn -> System.get_env("WEBHOOK_SECRET") end,
      on: [:pay]
  end
end
```

## Admin UI

Add FOSM admin routes to your router:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  import FosmWeb.Router

  scope "/", MyAppWeb do
    # Your routes...
  end

  # Add FOSM admin routes
  fosm_admin_routes()
end
```

The admin interface provides:
- Dashboard with all FOSM models
- Transition history and logs
- Role management
- Webhook configuration
- Settings

## Testing

### Testing State Transitions

```elixir
defmodule MyApp.InvoiceTest do
  use MyApp.DataCase
  alias MyApp.Invoice

  describe "lifecycle" do
    test "can transition from draft to sent" do
      invoice = insert(:invoice, state: "draft")

      {:ok, invoice} = Invoice.fire!(invoice, :send, actor: :system)

      assert invoice.state == "sent"
    end

    test "cannot pay from draft" do
      invoice = insert(:invoice, state: "draft")

      {:error, reason} = Invoice.fire!(invoice, :pay, actor: :system)

      assert reason =~ "Cannot fire 'pay' from state 'draft'"
    end
  end
end
```

### Testing Guards

```elixir
test "cannot pay negative amounts" do
  invoice = insert(:invoice, state: "sent", amount: Decimal.new("-10.00"))

  {:error, reason} = Invoice.fire!(invoice, :pay, actor: :system)

  assert reason =~ "Amount must be positive"
end
```

## Configuration

### Global Settings

```elixir
# config/config.exs
config :fosm,
  # Default snapshot configuration
  snapshot: [
    every_n_transitions: 10,
    on_terminate: true
  ],
  # Oban configuration for async operations
  oban: [
    queues: [
      fosm_webhooks: 10,
      fosm_side_effects: 20
    ]
  ]
```

### Per-Module Settings

```elixir
defmodule MyApp.Invoice do
  # ... schema ...

  # Enable snapshots for this model
  snapshot every: 5, on_terminate: true

  lifecycle do
    # ...
  end
end
```

## Next Steps

- [Architecture Overview](architecture.md) - Understand FOSM internals
- [Code Quality Guide](code_quality.md) - Setup quality tooling
- [Contributing](contributing.md) - Contribute to FOSM
