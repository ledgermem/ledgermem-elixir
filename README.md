# LedgerMem Elixir SDK

Official Elixir client for the [LedgerMem](https://proofly.dev) memory API.

## Install

```elixir
def deps do
  [{:ledgermem, "~> 0.1"}]
end
```

Then `mix deps.get`. Requires Elixir 1.15+ / OTP 26+.

## Quickstart

```elixir
{:ok, _pid} = LedgerMem.start_link(
  api_key: System.get_env("LEDGERMEM_API_KEY"),
  workspace_id: System.get_env("LEDGERMEM_WORKSPACE_ID")
)

{:ok, _memory} = LedgerMem.create("Shah prefers dark mode in terminals.")
{:ok, %{"hits" => hits}} = LedgerMem.search("ui preferences", limit: 5)

Enum.each(hits, fn h -> IO.puts("#{h["score"]} #{h["content"]}") end)
```

## Configuration

| Env var | Purpose |
| --- | --- |
| `LEDGERMEM_API_KEY` | Bearer token (required) |
| `LEDGERMEM_WORKSPACE_ID` | Workspace identifier (required) |
| `LEDGERMEM_API_URL` | Override base URL (default `https://api.proofly.dev`) |

## API

| Function | HTTP | Description |
| --- | --- | --- |
| `search(query, opts)` | `POST /v1/search` | Semantic + keyword search |
| `create(content, opts)` | `POST /v1/memories` | Store a new memory |
| `update(id, opts)` | `PATCH /v1/memories/:id` | Patch an existing memory |
| `delete(id)` | `DELETE /v1/memories/:id` | Remove a memory |
| `list(opts)` | `GET /v1/memories` | Paginated listing |

All functions return `{:ok, body}` or `{:error, %LedgerMem.Error{}}`.

## License

MIT
