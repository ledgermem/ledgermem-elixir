defmodule LedgerMem.Error do
  @moduledoc "Error returned from LedgerMem API calls."

  @type t :: %__MODULE__{status: integer(), message: String.t()}

  defexception [:status, :message]

  @impl true
  def message(%__MODULE__{status: status, message: msg}),
    do: "LedgerMem API error #{status}: #{msg}"
end
