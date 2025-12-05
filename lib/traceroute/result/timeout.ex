defmodule Traceroute.Result.Timeout do
  @moduledoc """
  Represents a hop that did not respond within the timeout period.

  When a router or destination doesn't respond to a probe packet,
  this result is recorded after all retries have been exhausted.
  """

  defstruct [:ttl, :retries]

  @type t :: %__MODULE__{
          ttl: pos_integer(),
          retries: non_neg_integer()
        }

  @doc """
  Creates a new Timeout result.
  """
  @spec new(ttl :: pos_integer(), retries :: non_neg_integer()) :: t()
  def new(ttl, retries \\ 0) do
    %__MODULE__{
      ttl: ttl,
      retries: retries
    }
  end
end
