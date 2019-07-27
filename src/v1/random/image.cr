require "random/secure"
require "crystar"
require "../partial"

module V1::Random
  # UncompressedLayer implements Partial::UncompressedLayer for raw bytes
  private class UncompressedLayer
    include V1::Partial::UncompressedLayer

    getter diff_id : V1::Hash
    @content : Bytes

    def initialize(@diff_id, @content)
    end

    # implements Partial::UncompressedLayer
    def uncompressed
      V1::Util::NoOpCloser.new IO::Memory.new @content
    end

    # returns the media type of the layer
    def media_type
      # Technically the media type should be 'application/tar' but given that our
      # v1.Layer doesn't force consumers to care about whether the layer is compressed
      # we should be fine returning the DockerLayer media type
      Types::DOCKERLAYER
    end
  end

  # Image is pseudo-randomly generated
  private class Image
    include V1::Partial::UncompressedImageCore
    include V1::Partial::WithConfigFile
    include V1::Partial::WithRawConfigFile

    getter config : V1::ConfigFile
    getter layers : ::Hash(V1::Hash, V1::Partial::UncompressedLayer)

    def initialize(@config, @layers); end

    def raw_config_file
      V1::Partial.raw_config_file(self)
    end

    def config_file
      @config
    end

    def media_type
      Types::DOCKERMANIFESTSCHEMA2
    end

    def layer_by_diff_id(h : V1::Hash)
      raise "unknown diff_id: #{h.to_s}" if !@layers.has_key?(h)
      @layers[h]
    end
  end
end
