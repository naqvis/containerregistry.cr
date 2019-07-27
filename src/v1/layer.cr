require "./hash"
require "./types"

module V1::Layer
  # Digest returns the Hash of the compressed layer.
  abstract def digest : V1::Hash
  # DiffID returns the Hash of the uncompressed layer.
  abstract def diff_id : V1::Hash
  # Compressed returns an io.ReadCloser for the compressed layer contents.
  abstract def compressed : IO
  # Uncompressed returns an io.ReadCloser for the uncompressed layer contents.
  abstract def uncompressed : IO
  # Size returns the compressed size of the layer
  abstract def size : Int64
  # MediaType returns the media type of the layer
  abstract def media_type : Types::MediaType
end
