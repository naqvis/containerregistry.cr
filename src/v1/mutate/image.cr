require "../partial"

module V1::Mutate
  private class Image
    include V1::Partial::WithRawManifest
    include V1::Partial::WithConfigFile
    include V1::Partial::WithRawConfigFile
    include V1::Image

    @base : V1::Image
    @adds : Array(Addendum)
    @computed : Bool = false
    @config_file : V1::ConfigFile?
    @manifest : V1::Manifest?

    def initialize(@base, @config_file = nil, @manifest = nil, @adds = Array(Addendum).new)
      @diff_id_map = ::Hash(V1::Hash, V1::Layer).new
      @digest_map = ::Hash(V1::Hash, V1::Layer).new
    end

    def media_type
      @base.media_type
    end

    def compute : Nil
      return if @computed # Don't re-compute if already computed
      config_file : V1::ConfigFile

      if (cf = @config_file)
        config_file = cf
      else
        cf = @base.config_file
        if cf.nil?
          raise "config file not found."
        else
          config_file = cf.dup
        end
      end

      diff_ids = config_file.rootfs.diff_ids
      history = config_file.history

      diff_id_map = ::Hash(V1::Hash, V1::Layer).new
      digest_map = ::Hash(V1::Hash, V1::Layer).new

      @adds.each do |add|
        diff_id = add.layer.diff_id
        diff_ids << diff_id
        if (h = history) && (hist = add.history)
          h << hist
        end
        diff_id_map[diff_id] = add.layer
      end
      manifest = @base.manifest.dup
      raise "manifest not found" if manifest.nil?
      manifest_layers = manifest.layers
      @adds.each do |add|
        d = V1::Descriptor.new(
          media_type: Types::DOCKERLAYER,
          size: add.layer.size,
          digest: add.layer.digest
        )
        manifest_layers << d
        digest_map[d.digest] = add.layer
      end

      config_file.rootfs.diff_ids = diff_ids
      config_file.history = history

      manifest.layers = manifest_layers

      rcfg = config_file.to_json
      d, sz = V1::Hash.sha256(IO::Memory.new(rcfg))
      manifest.config.digest = d
      manifest.config.size = sz

      @config_file = config_file
      @manifest = manifest
      @diff_id_map = diff_id_map
      @digest_map = digest_map
      @computed = true
    end

    # layers returns the ordered collection of filesystem layers that comprise this image.
    # The order of the list is oldest/base layer first, and most-recent/top layer last.
    def layers
      begin
        compute
      rescue V1::Stream::ExNotComputed
        # Image contains a streamable layer which has not yet been consumed.
        # Just return the layers we have in case the caller is going to consume the layers.
        layers = @base.layers
        @adds.each { |add| layers << add.layer }
        return layers
      end

      diff_ids = Partial.diff_ids(self)
      ls = Array(V1::Layer).new(diff_ids.size)
      diff_ids.each do |h|
        l = layer_by_diff_id h
        ls << l
      end
      ls
    end

    # config_name returns the hash of the image's config file
    def config_name
      compute
    rescue V1::Stream::ExNotComputed
      V1::Hash.empty
    else
      Partial.config_name(self)
    end

    # config_file returns this image's config file
    def config_file
      compute
      @config_file
    end

    # raw_config_file returns the serialized bytes of config_file
    def raw_config_file
      compute
      @config_file.to_json.to_slice
    end

    # digest returns the sha256 of this image's manifest
    def digest
      compute
    rescue V1::Stream::ExNotComputed
      V1::Hash.empty
    else
      Partial.digest(self)
    end

    # manifest returns this image's manifest object
    def manifest
      compute
      @manifest
    end

    # raw_manifest returns the serialized bytes of manifest
    def raw_manifest
      compute
      @manifest.to_json.to_slice
    end

    # layer_by_digest returns a layer for interacting with a particular layer of the image,
    # looking it up by "digest" (the compressed hash)
    def layer_by_digest(h : V1::Hash)
      if (cn = config_name)
        return Partial.config_layer(self) if h == cn
        return @digest_map[h] if @digest_map.has_key?(h)
        @base.layer_by_digest h
      else
        raise "Unable to find layer by digest #{h.to_s}"
      end
    end

    # layer_by_diff_id is an analog to layer_by_digest, looking up by "diff id" (the uncompressed hash)
    def layer_by_diff_id(h : V1::Hash)
      return @diff_id_map[h] if @diff_id_map.has_key?(h)
      @base.layer_by_diff_id h
    end
  end
end
