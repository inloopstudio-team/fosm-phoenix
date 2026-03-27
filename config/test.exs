import Config

# Configure your database for test environment
config :fosm, Fosm.Repo,
  database: "fosm_test#{System.get_env("MIX_TEST_PARTITION")}",
  username: System.get_env("DB_USER") || "postgres",
  password: System.get_env("DB_PASSWORD") || "postgres",
  hostname: System.get_env("DB_HOST") || "localhost",
  port: String.to_integer(System.get_env("DB_PORT") || "5545"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Configure Oban for testing (inline mode)
config :fosm, Oban,
  repo: Fosm.Repo,
  testing: :inline,
  queues: false,
  plugins: false

# FOSM test configuration
config :fosm,
  transition_log_strategy: :sync,  # Use sync in tests for predictability
  webhook_timeout: 5_000,
  max_webhook_retries: 3

# Print only warnings and errors during test
config :logger, level: :warning
