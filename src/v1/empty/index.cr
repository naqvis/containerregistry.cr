module V1::Empty
  private class EmptyIndex
    def media_type
      Types::OCIIMAGEINDEX
    end

    def digest
      Partial.digest(self)
    end

    def index_manifest
      V1::IndexManifest.new(schema_version: 2)
    end

    def raw_manifest
      im = index_manifest
      im.to_json.to_slice
    end

    def image(h : V1::Hash)
      raise "empty index"
    end

    def image_index(h : V1::Hash)
      raise "empty index"
    end
  end
end
