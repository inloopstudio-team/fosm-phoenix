import Config

# Runtime configuration - loaded after compilation

# Database configuration from DATABASE_URL if available (production)
if database_url = System.get_env("DATABASE_URL") do
  # Production: Use DATABASE_URL with PostgreSQL
  config :fosm, Fosm.Repo,
    adapter: Ecto.Adapters.Postgres,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: [:inet6],
    queue_target: 5000,
    queue_interval: 5000
else
  # No DATABASE_URL: Check if we need to configure a default for prod
  # In dev/test, the environment-specific configs take precedence
  if config_env() == :prod do
    # Production requires DATABASE_URL
    raise """
    DATABASE_URL environment variable is not set.

    To configure the database, set the DATABASE_URL with format:
      postgresql://USER:PASS@HOST/DATABASE

    For example:
      export DATABASE_URL="postgresql://postgres:postgres@localhost/fosm_prod"
    """
  end
end

# Oban configuration for production (repo set at runtime)
if config_env() == :prod do
  config :fosm, Oban,
    repo: Fosm.Repo,
    plugins: [
      {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 30}, # 30 days
      {Oban.Plugins.Cron, crontab: []}
    ],
    queues: [fosm_logs: 20, fosm_webhooks: 20, fosm_access: 10]
end

# Production environment configuration
config :fosm,
  # Must be configured at runtime
  repo: Fosm.Repo,
  transition_log_strategy: :async

# Logger configuration
config :logger, :console,
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :record_type, :record_id]
