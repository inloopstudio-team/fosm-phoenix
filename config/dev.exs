import Config

# Development environment configuration
config :fosm,
  repo: Fosm.Repo,
  transition_log_strategy: :sync

# Oban configuration (if enabled)
config :fosm, Oban,
  repo: Fosm.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}, # 7 days
    {Oban.Plugins.Cron, crontab: []}
  ],
  queues: [fosm_logs: 10, fosm_webhooks: 10, fosm_access: 10]

# Logger configuration
config :logger, :console,
  level: :debug,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
