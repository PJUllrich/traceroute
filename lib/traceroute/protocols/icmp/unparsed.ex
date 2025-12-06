defmodule Traceroute.Protocols.ICMP.Unparsed do
  @moduledoc """
  Represents an unparsed or unhandled ICMP message.

  This struct is returned when the ICMP type/code combination
  is not explicitly handled by the parser.
  """

  defstruct [:type, :code, :payload]

  @type t :: %__MODULE__{
          type: non_neg_integer() | nil,
          code: non_neg_integer() | nil,
          payload: binary()
        }
end
