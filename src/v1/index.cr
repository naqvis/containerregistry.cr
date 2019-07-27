require "./hash"
require "./types"

# ImageIndex defines the interface for interacting with an OCI image index.
module V1::ImageIndex
  # MediaType of this image's manifest.
  abstract def media_type : Types::MediaType

  # Digest returns the sha256 of this index's manifest
  abstract def digest : V1::Hash
  # index_manifest returns this image index's manifest object
  abstract def index_manifest : V1::IndexManifest
  # raw_manifest returns the serialized bytes of IndexManifest
  abstract def raw_manifest : Bytes
  # image returns a v1.Image that this ImageIndex references
  abstract def image(h : V1::Hash) : V1::Image
  # image returns a v1.ImageIndex that this ImageIndex references
  abstract def image_index(h : V1::Hash) : V1::ImageIndex
end
