require "../hash"
require "../layer"
require "./image"
require "./with"
require "../image"
require "../layer"
require "../remote/write"

module V1::Partial
  # UncompressedLayer represents the bare minimum interface a natively
  # uncompressed layer must implement for us to produce a v1.Layer
  module UncompressedLayer
    # diff_id returns the Hash of the uncompressed layer.
    abstract def diff_id : V1::Hash

    # uncompressed returns an IO for the uncompressed layer contents
    abstract def uncompressed : IO

    # returns the mediaType for the compressed layer
    abstract def media_type : Types::MediaType
  end

  # implements v1.Image using the uncompressed base properties.
  private class UnCompressedLayerExtender
    include UncompressedLayer
    include V1::Layer

    # Memoize size/hash so that the methods aren't twice as
    # expensive as doing this manually.
    @hash : V1::Hash = V1::Hash.empty
    @size : Int64 = 0
    @ule : UncompressedLayer

    def initialize(@ule)
      @once = V1::Util::Once.new
    end

    delegate diff_id, uncompressed, media_type, to: @ule

    # implements V1::Layer
    def compressed
      u = @ule.uncompressed
      V1::Util.gzip_reader_closer(u.reader)
    end

    # implements V1::Layer
    def digest
      calc_size_hash
      @hash
    end

    # implements V1::Layer
    def size
      calc_size_hash
      @size
    end

    private def calc_size_hash
      @once.do(Proc(Void).new {
        r = compressed
        begin
          @hash, @size = V1::Hash.sha256(r)
        ensure
          r.close
        end
      })
    end
  end

  # UncompressedImageCore represents the bare minimum interface a natively
  # uncompressed image must implement for us to produce V1::Image
  module UncompressedImageCore
    include ImageCore

    # layer_by_diff_id is a variation on the V1.image method, which returns
    # an UncompressedLayer instead.
    abstract def layer_by_diff_id(h : V1::Hash) : UncompressedLayer
  end

  # UncompressedImageExtender implements V1::Image by extending UncompressedImageCore with the
  # appropriate methods computed from the minimal core.
  private class UncompressedImageExtender
    include UncompressedImageCore
    include WithConfigFile
    include WithRawConfigFile
    include WithManifestAndConfigFile
    include V1::Partial::WithManifest
    include V1::Partial::WithRawManifest
    include V1::Remote::Manifest
    include V1::Image

    @uic : UncompressedImageCore
    getter lock : Mutex
    @manifest : V1::Manifest?

    delegate raw_config_file, media_type, to: @uic

    def initialize(@uic)
      @lock = Mutex.new
    end

    def digest
      Partial.digest(self)
    end

    # implements V1::Image
    def manifest
      lock.synchronize {
        return @manifest unless @manifest.nil?

        b = raw_config_file
        cfg_hash, cfg_size = Hash.sha256(IO::Memory.new(b))

        m = V1::Manifest.new(schema_version: 2,
          media_type: Types::DOCKERMANIFESTSCHEMA2,
          config: V1::Descriptor.new(
            media_type: Types::DOCKERCONFIGJSON,
            size: cfg_size,
            digest: cfg_hash
          ))
        ls = layers

        m.layers = Array(V1::Descriptor).new(ls.size)
        ls.each_with_index do |l, _|
          m.layers << V1::Descriptor.new(
            media_type: Types::DOCKERLAYER,
            size: l.size,
            digest: l.digest
          )
        end
        @manifest = m
      }
      @manifest
    end

    def raw_manifest
      Partial.raw_manifest(self)
    end

    def config_name
      Partial.config_name(self)
    end

    def config_file
      Partial.config_file(self)
    end

    def layers
      diff_ids = Partial.diff_ids(self)
      ls = Array(V1::Layer).new(diff_ids.size)
      diff_ids.each_with_index do |d, _|
        ls << layer_by_diff_id(d)
      end
      ls
    end

    def layer_by_diff_id(dif : V1::Hash)
      ul = @uic.layer_by_diff_id(dif)
      Partial.uncompressed_to_layer(ul)
    end

    def layer_by_digest(h : V1::Hash)
      diff_id = Partial.blob_to_diff_id(self, h)
      layer_by_diff_id(diff_id)
    end
  end
end
