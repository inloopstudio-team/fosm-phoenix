import Config

# Production environment configuration
config :fosm,
  # Must be configured at runtime
  repo: nil,
  transition_log_strategy: :async

# Oban configuration for production
config :fosm, Oban,
  repo: nil,
  # Configured at runtime
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 30}, # 30 days
    {Oban.Plugins.Cron, crontab: []}
  ],
  queues: [fosm_logs: 20, fosm_webhooks: 20, fosm_access: 10]

# Logger configuration
config :logger, :console,
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :record_type, :record_id]
