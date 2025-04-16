defmodule Adk.Test.Schemas do
  defmodule InputSchema do
    @derive {JSON.Encoder, only: [:query, :user_id]}
    @enforce_keys [:query]
    defstruct [:query, :user_id]
  end

  defmodule OutputSchema do
    @derive {JSON.Encoder, only: [:answer, :confidence]}
    @enforce_keys [:answer, :confidence]
    defstruct [:answer, :confidence]
  end
end
