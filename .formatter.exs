spark_locals_without_parens = [
  allow_nil?: 1,
  constraints: 1,
  description: 1,
  field: 2,
  field: 3,
  variant: 1,
  variant: 2
]

locals_without_parens = spark_locals_without_parens

# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter],
  import_deps: [:ash, :reactor],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ]
]
