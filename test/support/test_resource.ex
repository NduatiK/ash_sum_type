defmodule AshSumTypeTest.TestGameResource do
  use Ash.Resource,
    domain: AshSumTypeTest.TestGamesDomain,
    data_layer: Ash.DataLayer.Ets

  alias AshSumTypeTest.TicTacToeGameWinner

  ets do
    private? false
  end

  attributes do
    uuid_primary_key :id
    attribute :winner, TicTacToeGameWinner, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:winner]
    end
  end
end
