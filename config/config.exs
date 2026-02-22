# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :clearsight_news,
  ecto_repos: [ClearsightNews.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :clearsight_news, ClearsightNewsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ClearsightNewsWeb.ErrorHTML, json: ClearsightNewsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ClearsightNews.PubSub,
  live_view: [signing_salt: "X2Fe26W6"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :clearsight_news, ClearsightNews.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  clearsight_news: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  clearsight_news: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Instructor — use the Groq adapter globally.
# API key is read from GROQ_API_KEY env var by the adapter automatically.
config :instructor, adapter: Instructor.Adapters.Groq

# NewsAPI implementation — overridden to MockNewsApi in test env
config :clearsight_news, :news_api_impl, ClearsightNews.NewsApiService

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
