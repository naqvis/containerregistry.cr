require "../partial"
require "../remote/write"

module V1::Random
  private class RandomIndex
    include V1::Partial::WithRawManifest
    include V1::Partial::WithManifest
    include V1::Remote::Manifest
    include V1::ImageIndex

    getter images : ::Hash(V1::Hash, V1::Image)
    getter manifest : V1::IndexManifest

    def initialize(@images, @manifest)
    end

    def media_type
      Types::OCIIMAGEINDEX
    end

    def digest
      V1::Partial.digest(self)
    end

    def index_manifest
      @manifest
    end

    def raw_manifest
      m = index_manifest
      if m.nil?
        Bytes.empty
      else
        m.to_json.to_slice
      end
    end

    def image(h : V1::Hash)
      raise "Image not found: #{h.to_s}" unless @images.has_key?(h)
      @images[h]
    end

    def image_index(h : V1::Hash)
      # This is a single level index (for now?).
      raise "Single level index - Image not found: #{h.to_s}"
    end
  end
end
