defmodule AshSumTypeTest.Result do
  use AshSumType

  variant :ok do
    field :value, :integer, allow_nil?: false
  end

  variant :error do
    field :value, :string, allow_nil?: false
  end
end

defmodule AshSumTypeTest.TicTacToePlayer do
  use AshSumType

  variant :x
  variant :o
end

defmodule AshSumTypeTest.TicTacToeGameWinner do
  use AshSumType

  variant :player do
    field :player, AshSumTypeTest.TicTacToePlayer, allow_nil?: false
  end

  variant :draw
end
