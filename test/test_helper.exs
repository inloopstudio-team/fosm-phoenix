ExUnit.start()

# Ensure the Ecto repository and application are started for tests
# Database sandbox mode is set per-test in test/support/data_case.ex
alias Fosm.Repo

# Start the Ecto Sandbox for test isolation
Ecto.Adapters.SQL.Sandbox.mode(Fosm.Repo, :manual)

# Start Oban in testing mode (inline execution)
{:ok, _pid} = Oban.start_link(repo: Fosm.Repo, testing: :inline)
