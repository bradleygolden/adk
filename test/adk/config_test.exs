defmodule Adk.ConfigTest do
  use ExUnit.Case, async: false

  describe "config operations" do
    setup do
      # Reset any test environment variables before each test
      on_exit(fn ->
        Application.delete_env(:adk, :test_key)
      end)
    end

    test "set/2 and get/2 with string values" do
      Adk.Config.set(:test_key, "test_value")
      assert Adk.Config.get(:test_key) == "test_value"
    end

    test "set/2 and get/2 with atom values" do
      Adk.Config.set(:test_key, :atom_value)
      assert Adk.Config.get(:test_key) == :atom_value
    end

    test "set/2 and get/2 with map values" do
      config_map = %{a: 1, b: 2, c: 3}
      Adk.Config.set(:test_key, config_map)
      assert Adk.Config.get(:test_key) == config_map
    end

    test "get/2 with default value" do
      assert Adk.Config.get(:nonexistent_key) == nil
      assert Adk.Config.get(:nonexistent_key, "default") == "default"
    end

    test "get/2 after setting multiple values" do
      Adk.Config.set(:key1, "value1")
      Adk.Config.set(:key2, "value2")

      assert Adk.Config.get(:key1) == "value1"
      assert Adk.Config.get(:key2) == "value2"

      # Clean up after test
      Application.delete_env(:adk, :key1)
      Application.delete_env(:adk, :key2)
    end
  end
end
