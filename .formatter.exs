# Used by "mix format"
[
  import_deps: [:ecto, :ecto_sql, :phoenix, :phoenix_live_view, :oban],
  plugins: [],
  inputs: [
    "{mix,.formatter,.credo}.exs",
    "{config,lib,test,priv}/**/*.{ex,exs}",
    "apps/*/{config,lib,test}/**/*.{ex,exs}"
  ],
  line_length: 120,
  locals_without_parens: [
    # Ecto
    field: :*,
    belongs_to: :*,
    has_one: :*,
    has_many: :*,
    many_to_many: :*,
    embeds_one: :*,
    embeds_many: :*,
    
    # FOSM DSL
    lifecycle: :*,
    state: :*,
    event: :*,
    transition: :*,
    guard: :*,
    side_effect: :*,
    access: :*,
    role: :*,
    can: :*,
    snapshot: :*,
    webhook: :*,
    on: :*,
    from: :*,
    to: :*,
    when_guard: :*,
    after_effect: :*,
    
    # Phoenix/LiveView
    live: :*,
    scope: :*,
    pipe_through: :*,
    attr: :*,
    slot: :*
  ]
]
