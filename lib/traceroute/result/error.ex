defmodule Traceroute.Result.Error do
  @moduledoc """
  Represents a hop that returned an error during traceroute.

  This struct captures errors other than timeouts, such as network
  unreachable, host unreachable, or other ICMP error responses.
  """

  defstruct [:ttl, :reason]

  @type t :: %__MODULE__{
          ttl: pos_integer(),
          reason: atom() | term()
        }

  @doc """
  Creates a new Error result.
  """
  @spec new(pos_integer(), atom() | term()) :: t()
  def new(ttl, reason) do
    %__MODULE__{
      ttl: ttl,
      reason: reason
    }
  end
end
