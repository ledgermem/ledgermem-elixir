defmodule Mnemo do
  @moduledoc """
  Public API for the Mnemo Elixir client.

  Start a singleton client and call the wrapper functions:

      {:ok, _pid} = Mnemo.start_link(api_key: "...", workspace_id: "...")
      {:ok, hits} = Mnemo.search("hello")
  """

  alias Mnemo.Client

  @type opts :: keyword()
  @type result :: {:ok, map()} | {:error, Mnemo.Error.t()}

  defdelegate start_link(opts), to: Client
  defdelegate child_spec(opts), to: Client

  @spec search(String.t(), opts) :: result
  def search(query, opts \\ []), do: Client.search(query, opts)

  @spec create(String.t(), opts) :: result
  def create(content, opts \\ []), do: Client.create(content, opts)

  @spec update(String.t(), opts) :: result
  def update(id, opts \\ []), do: Client.update(id, opts)

  @spec delete(String.t()) :: :ok | {:error, Mnemo.Error.t()}
  def delete(id), do: Client.delete(id)

  @spec delete(String.t(), opts) :: :ok | {:error, Mnemo.Error.t()}
  def delete(id, opts), do: Client.delete(id, opts)

  @spec list(opts) :: result
  def list(opts \\ []), do: Client.list(opts)
end
