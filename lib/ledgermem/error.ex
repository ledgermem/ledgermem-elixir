defmodule Mnemo.Error do
  @moduledoc "Error returned from Mnemo API calls."

  @type t :: %__MODULE__{status: integer(), message: String.t()}

  defexception [:status, :message]

  @impl true
  def message(%__MODULE__{status: status, message: msg}),
    do: "Mnemo API error #{status}: #{msg}"
end
