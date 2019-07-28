require "../hash"
require "../image"
require "../layer"
require "./image"
require "./with"
require "../remote/write"

module V1::Partial
  # CompressedImageCore represents the base minimum interface a natively
  # compressed image must implement for us to produce a v1.Image.
  module CompressedImageCore
    include ImageCore

    # returns the serialized bytes of the manifest.
    abstract def raw_manifest : Bytes

    # variation on the V1 Image method, which returns
    # a compressed layer instead
    abstract def layer_by_digest(h : V1::Hash) : CompressedLayer
  end

  # CompressedLayer represents the bare minimum interface a natively
  # compressed layer must implement for us to produce a v1.Layer
  module CompressedLayer
    #  returns the Hash of the compressed layer.
    abstract def digest : V1::Hash
    # returns an IO for the compressed layer
    abstract def compressed : IO
    # returns the compressed size of the layer
    abstract def size : Int64
    # returns the media type of compressed layer
    abstract def media_type : Types::MediaType
  end

  # implements v1.Image using the compressed base properties.
  private class CompressedLayerExtender
    include CompressedLayer
    include V1::Layer

    @cl : V1::Layer | CompressedLayer

    def initialize(@cl)
    end

    delegate digest, compressed, size, media_type, to: @cl

    # implements V1::Layer
    def uncompressed : IO
      V1::Util.gunzip_reader_closer(compressed)
    end

    # implements V1::Layer
    def diff_id : V1::Hash
      # If our nested CompressedLayer implements DiffID,
      # then delegate to it instead

      if wdi = self.as?(WithDiffID)
        return wdi.diff_id
      end

      if r = uncompressed
        h, _ = V1::Hash.sha256(r)
        r.close
        return h
      end
      V1::Hash.new("", "")
    end
  end

  # compressedImageExtender implements v1.Image by extending CompressedImageCore with the
  # appropriate methods computed from the minimal core.
  private class CompressedImageExtender
    include CompressedImageCore
    include WithManifest
    include WithRawManifest
    include WithRawConfigFile
    include WithManifestAndConfigFile
    include V1::Remote::Manifest
    include V1::Image
    @cic : CompressedImageCore

    def initialize(@cic)
    end

    delegate raw_config_file, media_type, raw_manifest, to: @cic

    # Digest implements v1.Image
    def digest
      Partial.digest(self)
    end

    # config_name implements v1 image
    def config_name
      Partial.config_name(self)
    end

    # layers implements v1 image
    def layers
      hs = Partial.fs_layers(self)
      ls = Array(V1::Layer).new(hs.size)
      hs.each_with_index do |h, _|
        ls << layer_by_digest(h)
      end
      ls
    end

    # layer_by_digest implements v1 image
    def layer_by_digest(h : V1::Hash) : V1::Layer
      cl = @cic.layer_by_digest(h)
      Partial.compressed_to_layer(cl)
    end

    # layer_by_diff_id implements v1 image
    def layer_by_diff_id(h : V1::Hash) : V1::Layer
      h = Partial.diff_to_blob(self, h)
      layer_by_digest(h)
    end

    # config_file implements v1 image
    def config_file
      Partial.config_file(self)
    end

    # manifest implements v1 image
    def manifest
      Partial.manifest(self)
    end
  end
end
