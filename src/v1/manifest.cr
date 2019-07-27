require "json"
require "./types"
require "./platform"
require "./hash"

module V1
  # Manifest represents the OCI image manifest in a structured way.
  struct Manifest
    JSON.mapping(
      schema_version: {type: Int64, key: "schemaVersion", nilable: true},
      media_type: {type: Types::MediaType, key: "mediaType", converter: Types::MediaType, default: Types::MediaType[""]},
      config: Descriptor,
      layers: Array(Descriptor),
      annotations: {type: ::Hash(String, String), nilable: true},
    )

    def initialize(schema_version : Int, @media_type, @config)
      @schema_version = schema_version.to_i64
      @layers = Array(Descriptor).new
    end
  end

  # IndexManifest represents an OCI image index in a structured way.
  struct IndexManifest
    JSON.mapping(
      schema_version: {type: Int64, key: "schemaVersion", nilable: true},
      media_type: {type: Types::MediaType, key: "mediaType", nilable: true, converter: Types::MediaType},
      manifests: Array(Descriptor),
      annotations: {type: ::Hash(String, String), nilable: true},
    )

    def initialize(schema_version : Int, @manifests, @media_type = nil, @annotations = nil)
      @schema_version = schema_version.to_i64
    end
  end

  # Descriptor holds a reference from the manifest to one of its constituent elements.
  struct Descriptor
    JSON.mapping(
      media_type: {type: Types::MediaType, key: "mediaType", converter: Types::MediaType, default: Types::MediaType[""]},
      size: Int64,
      digest: {type: V1::Hash, converter: V1::Hash},
      urls: {type: Array(String), nilable: true},
      annotations: {type: ::Hash(String, String), nilable: true},
      platform: {type: Platform, default: V1::Platform.new}
    )

    def initialize(@media_type, @digest : V1::Hash, size : Int)
      @size = size.to_i64
      @platform = V1::Platform.new
    end
  end

  def self.parse_manifest(r : IO)
    Manifest.from_json(r.gets_to_end)
  end

  def self.parse_index_manifest(r : IO)
    IndexManifest.from_json(r.gets_to_end)
  end
end
