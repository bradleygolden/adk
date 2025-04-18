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

    @field_descriptions %{
      answer: "A natural language answer to the user's question.",
      confidence: "A float between 0 and 1 representing the model's confidence in the answer."
    }
    def field_descriptions, do: @field_descriptions
  end
end
