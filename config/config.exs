import Config

config :spark,
  formatter: [
    AshSumType: []
  ]

import_config "#{config_env()}.exs"
