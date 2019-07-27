module V1::Cache
  private class FakeLayer
    include V1::Layer

    def digest
      V1::Hash.empty
    end

    def diff_id
      V1::Hash.empty
    end

    def compressed
      IO::Memory.new ""
    end

    def uncompressed
      IO::Memory.new ""
    end

    def size
      0_i64
    end

    def media_type
      Types::MediaType[""]
    end
  end

  private class FakeImage
    include V1::Image

    def layers
      [] of V1::Layer
    end

    def media_type
      Types::MediaType[""]
    end

    def config_name
      V1::Hash.empty
    end

    def config_file
      raise "config_file called"
    end

    def raw_config_file
      raise "raw_config_file called"
    end

    def digest
      raise "digest called"
    end

    def manifest
      raise "manifest called"
    end

    def raw_manifest
      raise "raw_manifest called"
    end

    def layer_by_digest(h : V1::Hash)
      raise "layer_by_digest called"
    end

    def layer_by_diff_id(h : V1::Hash)
      raise "layer_by_diff_id called"
    end
  end

  # MemCache is an in-memory Cacher implementation.
  #
  # It doesn't intend to actually write layer data, it just keeps a reference
  # to the original Layer.
  #
  # It only assumes/considers compressed layers, and so only writes layers by
  # digest.

  private class MemCache < Cacher
    getter m : ::Hash(V1::Hash, V1::Layer)

    def initialize
      @m = ::Hash(V1::Hash, V1::Layer).new
    end

    def initialize(@m)
    end

    def size
      @m.size
    end

    def put(l : V1::Layer)
      digest = l.digest
      @m[digest] = l
      l
    end

    def get(h : V1::Hash)
      raise LayerNotFound.new("layer was not found") if !@m.has_key?(h)
      @m[h]
    end

    def delete(h : V1::Hash) : Nil
      @m.delete(h)
    end
  end
end
