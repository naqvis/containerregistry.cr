module V1::Remote
  # MountableLayer wraps a v1.Layer in a shim that enables the layer to be
  # "mounted" when published to another registry.
  class MountableLayer
    include V1::Layer
    getter layer : V1::Layer
    getter reference : Name::References

    delegate digest, diff_id, compressed, uncompressed, size, media_type, to: @layer

    def initialize(@layer, @reference)
    end
  end

  # mountableImage wraps the v1.Layer references returned by the embedded v1.Image
  # in MountableLayer's so that remote.Write might attempt to mount them from their
  # source repository.
  class MountableImage
    include V1::Partial::WithRawConfigFile
    include V1::Image
    @image : V1::Image
    @reference : Name::References

    delegate media_type, config_name, config_file, raw_config_file, digest, manifest, raw_manifest, to: @image

    def initialize(@image, @reference)
    end

    # Layers implements v1.Image
    def layers
      ls = @image.layers
      mls = Array(V1::Layer).new(ls.size)
      ls.each_with_index do |l, _|
        mls << MountableLayer.new(l, @reference)
      end
      mls
    end

    # Layer_by_digest implements v1.Image
    def layer_by_digest(d : V1::Hash)
      l = @image.layer_by_digest(d)
      if l.nil?
        raise "Unable to retrieve layer with digest #{d.to_s}"
      else
        MountableLayer.new(l, @reference)
      end
    end

    # Layer_by_diff_id implements v1.Image
    def layer_by_diff_id(d : V1::Hash)
      l = @image.layer_by_diff_id(d)
      MountableLayer.new(l, @reference)
    end
  end
end
