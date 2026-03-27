# FOSM Phoenix Implementation Summary

## Overview

Porting FOSM from Rails to Phoenix presents an opportunity to leverage Elixir's strengths while maintaining the core architectural principles that make FOSM valuable.

## Key Architectural Differences

### 1. Compile-Time DSL Validation
**Rails**: Runtime DSL evaluation via `instance_eval` on a Definition class
**Phoenix**: Compile-time macro expansion with `__using__` and `@before_compile`

**Advantage**: Elixir can validate lifecycle definitions at compile time, catching errors before runtime.

### 2. Concurrency Model
**Rails**: Thread-based with CurrentAttributes for per-request state
**Phoenix**: Process-based with Process dictionary or Agent for per-request state

**Advantage**: BEAM processes are lighter and more reliable than OS threads. The `Fosm.Current` cache using Process dictionary is simpler and faster than Rails' CurrentAttributes.

### 3. Background Jobs
**Rails**: ActiveJob with SolidQueue adapter
**Phoenix**: Oban with PostgreSQL backing

**Advantage**: Oban provides atomic job scheduling, retries with backoff, job unique constraints, and better observability out of the box.

### 4. Admin UI
**Rails**: Server-rendered ERB views with Turbo/ActionCable for reactivity
**Phoenix**: LiveView for true reactive UI without JavaScript frameworks

**Advantage**: LiveView provides a much better developer experience and end-user experience for the admin dashboard, with real-time updates built-in.

### 5. State Machine Execution
**Rails**: `SELECT FOR UPDATE` with ActiveRecord transactions
**Phoenix**: Ecto.Multi with explicit row locking via raw SQL

**Challenge**: Ecto doesn't have built-in pessimistic locking, so we need raw SQL for `SELECT FOR UPDATE`.

## Implementation Strategy

### Week 1: Foundation
- Set up project structure with proper namespaces
- Implement core `Fosm.Lifecycle` macro with compile-time DSL
- Create error types and basic configuration
- Write first tests

### Week 2: Persistence & Transitions
- Create Ecto schemas for all FOSM tables
- Write migrations
- Implement `fire!` with row locking
- Add guard and side effect execution

### Week 3: RBAC & Caching
- Implement `Fosm.Current` with Process dictionary
- Create RoleAssignment and AccessEvent schemas
- Add auto-role assignment on create
- Test RBAC enforcement

### Week 4: Async Processing
- Set up Oban
- Implement transition log job
- Implement webhook delivery job with HMAC
- Build transition buffer GenServer

### Week 5: Admin UI
- Build LiveView dashboard
- Create app detail page with lifecycle visualization
- Build role management interface
- Add transition log viewer

### Week 6: AI Agent
- Choose and integrate Instructor or custom tool calling
- Build tool generation from lifecycle definition
- Create agent explorer page
- Build agent chat interface

### Week 7: Generators & Polish
- Create `mix fosm.gen.app` task
- Build templates for all generated files
- Write comprehensive documentation
- Final testing and optimization

## Risk Areas

1. **Row Locking**: Ecto doesn't support pessimistic locking natively. Need careful handling with raw SQL.

2. **AI Agent Framework**: No direct Gemlings equivalent. Need to evaluate Instructor vs LangChainElixir vs custom implementation.

3. **Connection Pooling**: Rails has role-based multi-database support. In Phoenix, need to decide between shared repo vs dynamic repos.

4. **Deferred Side Effects**: Rails' `after_commit` callback is well-established. Phoenix needs equivalent using Ecto.Multi or process messaging.

## Recommended Libraries

| Function | Library | Notes |
|----------|---------|-------|
| Background Jobs | Oban | Industry standard for Phoenix |
| HTTP Client | Req | Modern, ergonomic HTTP client |
| JSON | Jason | Fast JSON encoding/decoding |
| LLM Integration | Instructor | Structured outputs from LLMs |
| Charts | Contex or VegaLite | For state distribution charts |
| Icons | Heroicons | For admin UI |

## Directory Structure

```
fosm/
├── lib/
│   ├── fosm/
│   │   ├── lifecycle/
│   │   │   ├── definition.ex
│   │   │   ├── state_definition.ex
│   │   │   ├── event_definition.ex
│   │   │   ├── guard_definition.ex
│   │   │   ├── side_effect_definition.ex
│   │   │   ├── access_definition.ex
│   │   │   ├── role_definition.ex
│   │   │   └── snapshot_configuration.ex
│   │   ├── lifecycle.ex              # Main DSL
│   │   ├── lifecycle/implementation.ex
│   │   ├── current.ex                # RBAC cache
│   │   ├── transition_buffer.ex
│   │   ├── registry.ex
│   │   ├── configuration.ex
│   │   ├── errors.ex
│   │   ├── agent.ex                  # Base agent
│   │   └── repo.ex                   # Repo wrapper
│   │
│   ├── fosm_web/
│   │   ├── live/
│   │   │   ├── admin/
│   │   │   │   ├── dashboard_live.ex
│   │   │   │   ├── app_detail_live.ex
│   │   │   │   ├── roles_live.ex
│   │   │   │   ├── transitions_live.ex
│   │   │   │   ├── webhooks_live.ex
│   │   │   │   └── agent/
│   │   │   │       ├── explorer_live.ex
│   │   │   │       └── chat_live.ex
│   │   │   └── shared/
│   │   ├── components/
│   │   ├── layouts/
│   │   └── router.ex
│   │
│   └── mix/
│       └── tasks/
│           └── fosm.gen.app.ex
│
├── priv/
│   ├── repo/migrations/
│   └── templates/
│       ├── model.ex.eex
│       ├── controller.ex.eex
│       ├── agent.ex.eex
│       ├── migration.ex.eex
│       └── views/
│
└── test/
```

## Next Steps

1. **Decision on AI Framework**: Evaluate Instructor vs LangChainElixir for the agent functionality
2. **Database Strategy**: Decide between shared repo vs dynamic repos for connection handling
3. **Prototype**: Build a minimal working example with one lifecycle (e.g., Invoice)
4. **Testing Strategy**: Set up test fixtures and patterns for lifecycle testing
5. **Documentation**: Start writing guides as we build

## Questions to Resolve

1. Should we use `Ecto.Multi` for all transactions or manual transaction handling?
2. How to best handle deferred side effects (spawn process vs Oban job)?
3. Which charting library for state distribution visualization?
4. Should the admin UI be a separate dependency or built-in?
5. How to handle multi-tenancy (if needed)?

## Conclusion

Porting FOSM to Phoenix is feasible and offers significant advantages in terms of:
- Real-time admin UI via LiveView
- More reliable background job processing via Oban
- Better concurrency handling via BEAM processes
- Compile-time validation of lifecycle definitions

Estimated timeline: 6-8 weeks for full feature parity.
