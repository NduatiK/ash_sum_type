defmodule AshSumTypeTest.Result do
  use AshSumType

  variant :ok do
    field :value, :integer
  end

  variant :error do
    field :value, :string
  end
end

defmodule AshSumTypeTest.MaybeLabel do
  use AshSumType

  variant :some do
    field :value, :string, allow_nil?: true
  end

  variant :none
end

defmodule AshSumTypeTest.TicTacToePlayer do
  use AshSumType

  variant :x
  variant :o
end

defmodule AshSumTypeTest.TicTacToeGameWinner do
  use AshSumType

  variant :player do
    field :player, AshSumTypeTest.TicTacToePlayer
  end

  variant :draw
end
