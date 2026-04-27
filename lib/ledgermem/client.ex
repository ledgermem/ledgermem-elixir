defmodule LedgerMem.Client do
  @moduledoc """
  GenServer-backed singleton wrapping a `Req` HTTP client.

  Holds the configured base URL and default headers. The actual HTTP work
  runs in the caller process via `Req` so the GenServer never blocks.
  """

  use GenServer

  alias LedgerMem.Error

  @default_base_url "https://api.proofly.dev"
  @version "0.1.0"
  @name __MODULE__

  # ---- Lifecycle ----

  def start_link(opts) do
    name = Keyword.get(opts, :name, @name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    api_key =
      Keyword.get(opts, :api_key) ||
        System.get_env("LEDGERMEM_API_KEY") ||
        raise ArgumentError, "api_key is required"

    workspace_id =
      Keyword.get(opts, :workspace_id) ||
        System.get_env("LEDGERMEM_WORKSPACE_ID") ||
        raise ArgumentError, "workspace_id is required"

    base_url =
      Keyword.get(opts, :base_url) ||
        System.get_env("LEDGERMEM_API_URL") ||
        @default_base_url

    req =
      Keyword.get(opts, :req) ||
        Req.new(
          base_url: String.trim_trailing(base_url, "/"),
          headers: [
            {"authorization", "Bearer " <> api_key},
            {"x-workspace-id", workspace_id},
            {"user-agent", "ledgermem-elixir/#{@version}"}
          ],
          receive_timeout: 30_000
        )

    {:ok, %{req: req}}
  end

  # ---- Public API ----

  def search(query, opts \\ []) do
    body =
      %{"query" => query}
      |> maybe_put("limit", Keyword.get(opts, :limit))
      |> maybe_put("actorId", Keyword.get(opts, :actor_id))

    request(opts, :post, "/v1/search", json: body)
  end

  def create(content, opts \\ []) do
    body =
      %{"content" => content}
      |> maybe_put("metadata", Keyword.get(opts, :metadata))
      |> maybe_put("actorId", Keyword.get(opts, :actor_id))

    request(opts, :post, "/v1/memories", json: body)
  end

  def update(id, opts \\ []) do
    body =
      %{}
      |> maybe_put("content", Keyword.get(opts, :content))
      |> maybe_put("metadata", Keyword.get(opts, :metadata))

    request(opts, :patch, "/v1/memories/" <> URI.encode(id), json: body)
  end

  def delete(id, opts \\ []) do
    case request(opts, :delete, "/v1/memories/" <> URI.encode(id), []) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  def list(opts \\ []) do
    params =
      []
      |> maybe_put_kw(:limit, Keyword.get(opts, :limit))
      |> maybe_put_kw(:cursor, Keyword.get(opts, :cursor))
      |> maybe_put_kw(:actorId, Keyword.get(opts, :actor_id))

    request(opts, :get, "/v1/memories", params: params)
  end

  # ---- Internals ----

  defp request(caller_opts, method, path, req_opts) do
    name = Keyword.get(caller_opts, :name, @name)
    %{req: req} = GenServer.call(name, :get_state)

    case Req.request(req, [method: method, url: path] ++ req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body || %{}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, %Error{status: status, message: format(body)}}

      {:error, exception} ->
        {:error, %Error{status: 0, message: Exception.message(exception)}}
    end
  end

  defp format(body) when is_binary(body), do: body
  defp format(body), do: inspect(body)

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp maybe_put_kw(kw, _k, nil), do: kw
  defp maybe_put_kw(kw, k, v), do: Keyword.put(kw, k, v)

  # ---- GenServer ----

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}
end
