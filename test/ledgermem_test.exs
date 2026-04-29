defmodule MnemoTest do
  use ExUnit.Case, async: true

  setup do
    # Capture the inbound request so assertions can inspect it.
    test_pid = self()

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:req, conn.method, conn.request_path, conn.req_headers, body})

      response =
        case {conn.method, conn.request_path} do
          {"POST", "/v1/search"} ->
            ~s({"hits":[{"id":"m1","content":"hi","score":0.9}]})

          {"POST", "/v1/memories"} ->
            ~s({"id":"m_42","content":"remember","createdAt":"2026-01-01T00:00:00Z"})

          {"DELETE", "/v1/memories/missing"} ->
            conn = Plug.Conn.put_status(conn, 404)
            Plug.Conn.send_resp(conn, 404, ~s({"error":"not found"}))
        end

      case response do
        body when is_binary(body) ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, body)

        sent ->
          sent
      end
    end

    req = Req.new(plug: plug, base_url: "https://api.test")

    {:ok, pid} =
      Mnemo.Client.start_link(
        api_key: "test-key",
        workspace_id: "ws_123",
        req: req,
        name: :test_client
      )

    %{pid: pid}
  end

  test "search sends bearer + workspace headers and returns hits" do
    # Force the request through our named test client by re-resolving state.
    # Use the underlying GenServer name explicitly.
    {:ok, body} = Mnemo.Client.search("hello", limit: 3, name: :test_client)

    assert %{"hits" => [%{"id" => "m1", "score" => 0.9}]} = body

    assert_received {:req, "POST", "/v1/search", headers, raw_body}
    assert {"authorization", "Bearer test-key"} in headers
    assert {"x-workspace-id", "ws_123"} in headers
    assert raw_body =~ ~s("query":"hello")
    assert raw_body =~ ~s("limit":3)
  end

  test "create posts to /v1/memories" do
    {:ok, body} = Mnemo.Client.create("remember", name: :test_client)
    assert body["id"] == "m_42"
    assert_received {:req, "POST", "/v1/memories", _headers, _body}
  end

  test "delete returns error tuple on non-2xx" do
    assert {:error, %Mnemo.Error{status: 404}} =
             Mnemo.Client.delete("missing", name: :test_client)
  end
end
