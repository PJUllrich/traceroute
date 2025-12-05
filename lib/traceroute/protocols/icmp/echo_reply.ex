defmodule Traceroute.Protocols.ICMP.EchoReply do
  @moduledoc """
  Represents an ICMP Echo Reply message (type 0, code 0).

  This is the response to an Echo Request (ping), indicating that
  the destination host is reachable and responding.
  """

  defstruct [:identifier, :sequence, :data]

  @type t :: %__MODULE__{
          identifier: non_neg_integer(),
          sequence: non_neg_integer(),
          data: binary()
        }

  @doc """
  Parses an Echo Reply from the ICMP payload.
  """
  @spec parse(binary()) :: t()
  def parse(payload) do
    <<identifier::16, sequence::16, data::binary>> = payload

    %__MODULE__{
      identifier: identifier,
      sequence: sequence,
      data: data
    }
  end
end
