# Image defines the interface for interacting with an OCI v1 image.

module V1::Image
  # Layers returns the ordered collection of filesystem layers that comprise this image.
  # The order of the list is oldest/base layer first, and most-recent/top layer last.
  abstract def layers : Array(V1::Layer)
  # MediaType of this image's manifest.
  abstract def media_type : Types::MediaType
  # config_name returns the hash of the image config file
  abstract def config_name : V1::Hash
  # config_file returns this image's config file.
  abstract def config_file : V1::ConfigFile

  # raw_config_file returns the serialized bytes of ConfigFile
  abstract def raw_config_file : Bytes

  # digest returns the sha256 of this image's manifest
  abstract def digest : V1::Hash

  # manifest returns this image's Manifest
  abstract def manifest : V1::Manifest
  # raw_manifest returns the serialized bytes of Manifes
  abstract def raw_manifest : Bytes
  # layer_by_digest returns a Layer for interacting with a particular layer of
  # the image, looking it up by "digest" (the compressed hash).
  abstract def layer_by_digest(h : V1::Hash) : V1::Layer

  # layer_by_diff_id is an analog to layer_by_digest, looking up by "diff id"
  # (the uncompressed hash).
  abstract def layer_by_diff_id(h : V1::Hash) : V1::Layer
end
