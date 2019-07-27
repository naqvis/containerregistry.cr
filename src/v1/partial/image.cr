require "../types"

module V1::Partial
  # imageCore is the core set of properties without which we cannot build a v1.Image
  module ImageCore
    # returns the serialized bytes of this image's config file.
    abstract def raw_config_file : Bytes
    abstract def media_type : Types::MediaType
  end
end
