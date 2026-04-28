defmodule LedgerMem.Client do
  @moduledoc """
  GenServer-backed singleton wrapping a `Req` HTTP client.

  Holds the configured base URL and default headers. The actual HTTP work
  runs in the caller process via `Req` so the GenServer never blocks.
  """

  use GenServer

  require Bitwise

  alias LedgerMem.Error

  @default_base_url "https://api.proofly.dev"
  @version "0.1.0"
  @name __MODULE__
  @default_max_retries 3
  @retry_base_delay_ms 200
  @retry_max_delay_ms 5_000

  # ---- Lifecycle ----

  def start_link(opts) do
    name = Keyword.get(opts, :name, @name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    with {:ok, api_key} <- fetch_required(opts, :api_key, "LEDGERMEM_API_KEY"),
         {:ok, workspace_id} <- fetch_required(opts, :workspace_id, "LEDGERMEM_WORKSPACE_ID") do
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

      max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
      {:ok, %{req: req, max_retries: max(0, max_retries)}}
    end
  end

  # Returning {:stop, reason} from init/1 is the supervisor-friendly way to
  # signal a misconfiguration without raising an ArgumentError that would
  # crash the supervision tree on the way up.
  defp fetch_required(opts, key, env) do
    case Keyword.get(opts, key) || System.get_env(env) do
      nil -> {:stop, {:missing_config, key}}
      "" -> {:stop, {:missing_config, key}}
      value -> {:ok, value}
    end
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

    request(opts, :patch, "/v1/memories/" <> encode_path_segment(id), json: body)
  end

  def delete(id, opts \\ []) do
    case request(opts, :delete, "/v1/memories/" <> encode_path_segment(id), []) do
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
    %{req: req, max_retries: max_retries} = GenServer.call(name, :get_state)
    do_request(req, method, path, req_opts, max_retries, 0)
  end

  defp do_request(req, method, path, req_opts, max_retries, attempt) do
    case Req.request(req, [method: method, url: path] ++ req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body || %{}}

      # 501 Not Implemented is permanent — fall through to the error path.
      {:ok, %Req.Response{status: 501, body: body}} ->
        {:error, %Error{status: 501, message: format(body)}}

      {:ok, %Req.Response{status: status, body: body, headers: headers}}
      when status == 429 or status in 500..599 ->
        if attempt < max_retries do
          Process.sleep(retry_delay(attempt, headers))
          do_request(req, method, path, req_opts, max_retries, attempt + 1)
        else
          {:error, %Error{status: status, message: format(body)}}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, %Error{status: status, message: format(body)}}

      {:error, exception} ->
        if attempt < max_retries and retryable_transport?(exception) do
          Process.sleep(retry_delay(attempt, []))
          do_request(req, method, path, req_opts, max_retries, attempt + 1)
        else
          {:error, %Error{status: 0, message: Exception.message(exception)}}
        end
    end
  end

  # Distinguish transient transport errors from permanent ones so we don't
  # waste retries on misconfiguration (e.g. unknown host).
  defp retryable_transport?(%Mint.TransportError{reason: reason}) do
    reason in [:timeout, :closed, :econnrefused, :econnreset, :ehostunreach, :enetunreach]
  end

  defp retryable_transport?(_), do: true

  # Exponential backoff with full jitter, capped at @retry_max_delay_ms.
  # Honours a Retry-After header when present.
  defp retry_delay(attempt, headers) do
    case retry_after_ms(headers) do
      nil ->
        capped = min(@retry_base_delay_ms * Bitwise.bsl(1, min(attempt, 20)), @retry_max_delay_ms)
        :rand.uniform(capped + 1) - 1

      hint ->
        min(hint, @retry_max_delay_ms)
    end
  end

  defp retry_after_ms(headers) do
    headers
    |> Enum.find_value(fn
      {k, v} when is_binary(k) ->
        if String.downcase(k) == "retry-after", do: v, else: nil

      _ ->
        nil
    end)
    |> case do
      nil ->
        nil

      [v | _] when is_binary(v) ->
        parse_retry_after(v)

      v when is_binary(v) ->
        parse_retry_after(v)

      _ ->
        nil
    end
  end

  defp parse_retry_after(raw) do
    case Integer.parse(String.trim(raw)) do
      {secs, ""} when secs >= 0 -> secs * 1000
      _ -> nil
    end
  end

  # Percent-encode a path segment per RFC 3986. Unlike URI.encode/1 this
  # encodes "/" and other reserved characters so an id containing them
  # cannot break out into additional path segments.
  defp encode_path_segment(s) when is_binary(s) do
    URI.encode(s, fn ch ->
      ch in ?A..?Z or ch in ?a..?z or ch in ?0..?9 or ch in [?-, ?_, ?., ?~]
    end)
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
