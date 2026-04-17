defmodule AshSumTypeTest.TestGamesDomain do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshSumTypeTest.TestGameResource do
      define :create_game, action: :create, args: [:winner]
      define :get_game, action: :read, get_by: [:id]
    end
  end
end
