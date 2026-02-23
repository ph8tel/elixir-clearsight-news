defmodule ClearsightNews.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ClearsightNewsWeb.Telemetry,
      ClearsightNews.Repo,
      {DNSCluster, query: Application.get_env(:clearsight_news, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ClearsightNews.PubSub},
      {Task.Supervisor, name: ClearsightNews.TaskSupervisor},
      ClearsightNews.Cleaner,
      # Start to serve requests, typically the last entry
      ClearsightNewsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ClearsightNews.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ClearsightNewsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
