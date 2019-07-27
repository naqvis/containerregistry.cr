require "json"

module V1::Remote
  private struct Tags
    JSON.mapping(
      name: {type: String, nilable: true},
      tags: Array(String)
    )
  end
end
