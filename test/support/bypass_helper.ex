defmodule Adk.BypassHelper do
  @moduledoc """
  Helper module for setting up Bypass in tests.
  """

  def setup_bypass do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  def build_chat_completion_response(content) do
    %{
      "id" => "chatcmpl-123",
      "object" => "chat.completion",
      "created" => 1_677_652_288,
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => content
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => 9,
        "completion_tokens" => 12,
        "total_tokens" => 21
      }
    }
  end

  def expect_langchain_request(bypass, method, path, response) when is_binary(response) do
    expect_langchain_request(bypass, method, path, build_chat_completion_response(response))
  end

  def expect_langchain_request(bypass, method, path, response) do
    Bypass.expect_once(bypass, method, path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, JSON.encode!(response))
    end)
  end

  def expect_langchain_error(bypass, method, path, status_code, error) do
    Bypass.expect_once(bypass, method, path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status_code, JSON.encode!(error))
    end)
  end

  def get_bypass_url(bypass) do
    "http://localhost:#{bypass.port}"
  end
end
