# Used by "mix format"
[
  import_deps: [:ecto, :ecto_sql, :phoenix_mountable],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: [event: 1, event: 2, version: 1, version: 2],
  export: [locals_without_parens: [event: 1, event: 2, version: 1, version: 2]]
]
