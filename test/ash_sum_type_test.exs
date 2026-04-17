defmodule AshSumTypeTest do
  use ExUnit.Case, async: true

  alias AshSumTypeTest.Result
  alias AshSumTypeTest.TicTacToePlayer
  alias AshSumTypeTest.TicTacToeMark
  alias AshSumTypeTest.TicTacToeGameWinner
  alias AshSumTypeTest.TestGamesDomain

  test "constructs tuple-backed values from named fields" do
    assert Result.new(:ok, value: 1) == {:ok, {:ok, 1}}
    assert Result.new(:error, value: "not found") == {:ok, {:error, "not found"}}
    assert Result.new({:ok, 1}) == {:ok, {:ok, 1}}
  end

  test "validates arguments using Ash types" do
    assert {:error, error} = Result.new(:ok, value: "nope")
    assert Exception.message(error) =~ "Invalid value provided"
  end

  test "stores zero-field variants as bare atoms" do
    assert TicTacToePlayer.new(:x) == {:ok, :x}
    assert TicTacToePlayer.cast_input(:o, []) == {:ok, :o}

    assert {:error, [field: :variant, message: message, value: {:o}]} =
             TicTacToePlayer.cast_input({:o}, [])

    assert message =~ "bare atoms"
  end

  test "supports nullary variants declared with the variants shorthand" do
    assert TicTacToeMark.variant_names() == [:x, :o]
    assert TicTacToeMark.new(:x) == {:ok, :x}
    assert TicTacToeMark.cast_input(:o, []) == {:ok, :o}
    assert TicTacToeMark.dump_to_native(:x, []) == {:ok, %{__variant__: :x}}
  end

  test "supports nesting one sum type inside another" do
    assert TicTacToeGameWinner.new(:player, player: :x) == {:ok, {:player, :x}}
    assert TicTacToeGameWinner.cast_input(:draw, []) == {:ok, :draw}
  end

  test "stores values as maps in the database representation" do
    assert {:ok, dumped} = Result.dump_to_native({:ok, 1}, [])
    assert dumped == %{__variant__: :ok, value: 1}
    assert Result.cast_stored(dumped, []) == {:ok, {:ok, 1}}
    assert TicTacToePlayer.dump_to_native(:o, []) == {:ok, %{__variant__: :o}}
    assert TicTacToePlayer.cast_stored(%{__variant__: :o}, []) == {:ok, :o}
    assert Result.storage_type([]) == :map
  end

  test "rejects unknown variants and wrong tuple arity" do
    assert :error = Result.cast_input(%{}, [])

    assert {:error, error} = Result.new(:wat, value: 1)
    assert Exception.message(error) =~ "unknown variant"

    assert {:error, [field: :ok, message: message, value: []]} = Result.cast_input({:ok}, [])
    assert message =~ "expected 1 argument"
  end

  test "works as an Ash resource attribute type with default values" do
    game = TestGamesDomain.create_game!({:player, :x})
    assert game.default_winner == :draw
  end

  test "works as an Ash resource attribute type with the ETS data layer" do
    game = TestGamesDomain.create_game!({:player, :x})
    assert game.winner == {:player, :x}

    reloaded = TestGamesDomain.get_game!(game.id)
    assert reloaded.winner == {:player, :x}
  end
end
