import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :clearsight_news, ClearsightNews.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "clearsight_news_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :clearsight_news, ClearsightNewsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "0bzte93LqKiXb4N6xUmUwLNPsVECZ6VERrnaHdfyQK+0ALyu2tZYRvuZN3zudZcV",
  server: false

# In test we don't send emails
config :clearsight_news, ClearsightNews.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Use the Mox mock for NewsAPI in tests — no real HTTP calls
config :clearsight_news, :news_api_impl, ClearsightNews.MockNewsApi

# Stub GROQ key so instructor_config/0 includes it; Req.Test intercepts the call.
config :clearsight_news,
  groq_api_key: "test-groq-key",
  instructor_http_options: [plug: {Req.Test, :groq_api}]

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
