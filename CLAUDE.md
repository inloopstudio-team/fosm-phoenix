# CLAUDE.md

<!-- fosm:agent-instructions -->
## FOSM (invoice)

This project uses `fosm-phoenix` — a Finite Object State Machine engine.
When working with Invoice or any FOSM resources, follow these conventions:

### Key FOSM Conventions

1. **State changes ONLY via `fire!`** - Never direct Ecto updates to the state field
2. **Guards are pure functions** - No side effects in guard blocks
3. **Side effects can be deferred** - Use `defer: true` for cross-machine triggers
4. **Every transition is logged** - Immutable audit trail in `fosm_transition_logs`
5. **RBAC is role-based** - Check `Elixir.Fosm.Fosm.Current.roles_for/3` for permissions

### Invoice State Machine

States: draft, sent, paid, void
Initial: draft
Terminal: paid, void

### Example Usage

```elixir
# Create in initial state
{:ok, <%= ctx.resource_path %>} = %<%= ctx.schema_module %>{}
  |> <%= ctx.schema_module %>.changeset(%{<%= example_fields(ctx.fields) %>state: :<%= get_initial_state(ctx.states) %>})
  |> <%= ctx.app_module %>.Repo.insert()

# Transition via event
{:ok, <%= ctx.resource_path %>} = <%= ctx.schema_module %>.fire!(<%= ctx.resource_path %>, :complete, actor: current_user)
```
