import Config

# Ecto repositories
config :fosm, ecto_repos: [Fosm.Repo]

config :fosm, Fosm.Repo,
  database: "fosm_dev",
  username: System.get_env("DB_USER") || "postgres",
  password: System.get_env("DB_PASSWORD") || "postgres",
  hostname: System.get_env("DB_HOST") || "localhost",
  port: String.to_integer(System.get_env("DB_PORT") || "5545"),
  pool_size: 10,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

# Configure Oban for background jobs
config :fosm, Oban,
  repo: Fosm.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},  # 7 days
    {Oban.Plugins.Cron, crontab: [
      {"0 0 * * *", Fosm.Jobs.CleanupJob}  # Daily cleanup
    ]}
  ],
  queues: [
    fosm_logs: 10,
    fosm_webhooks: 20,
    default: 10
  ]

# FOSM-specific configuration
config :fosm,
  transition_log_strategy: :async,  # :sync | :async | :buffered
  default_snapshot_strategy: :manual,  # :every | :count | :time | :terminal | :manual
  rbac_cache_ttl: :infinity,  # or seconds
  webhook_timeout: 30_000,  # 30 seconds
  max_webhook_retries: 10

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :elixir, :ansi_enabled, true
