# Cache encapsulates methods to interact with cached layers.
module V1::Cache
  # Exception raised by get when no layer with given hash is found
  class LayerNotFound < Exception
  end

  abstract class Cacher
    # Put writes the Layer to the Cache.
    #
    # The returned Layer should be used for future operations, since lazy
    # cachers might only populate the cache when the layer is actually
    # consumed.
    #
    # The returned layer can be consumed, and the cache entry populated,
    # by calling either Compressed or Uncompressed and consuming the
    # returned IO.

    abstract def put(l : V1::Layer) : V1::Layer

    # get returns the Layer cached by the given hash, or
    # raises NotFound exception if no such layer was found
    abstract def get(h : V1::Hash) : V1::Layer

    # delete  removes the Layer with the given Hash from the Cache.
    abstract def delete(h : V1::Hash)
  end

  def self.image(i : V1::Image, c : Cacher)
    Image.new(i, c)
  end

  private class Image
    include V1::Image
    @image : V1::Image
    @cache : Cacher

    delegate media_type, config_name, config_file, raw_config_file, digest, manifest, raw_manifest, to: @image

    def initialize(@image, @cache)
    end

    def layers
      ls = @image.layers
      res = Array(V1::Layer).new
      ls.each do |l|
        # Check if this layer is present in the cache in compressed form
        digest = l.digest
        begin
          cl = @cache.get digest
          # Layer found in the cache
          V1::Logger.info "Layer #{digest.to_s} found (compressed) in cache"
          res << cl
          next
        rescue LayerNotFound
        end

        # Check if this layer is present in the cache in uncompressed form.
        diff_id = l.diff_id
        begin
          cl = @cache.get diff_id
          # Layer found in the cache
          V1::Logger.info "Layer #{diff_id.to_s} found (uncompressed) in cache"
          res << cl
          next
        rescue LayerNotFound
        end

        # Not cached, fall through to real layer.
        l = @cache.put(l)
        res << l
      end
      res
    end

    def layer_by_digest(h : V1::Hash)
      @cache.get h
    rescue LayerNotFound
      # Not cached, get it and write it
      l = @image.layer_by_digest(h)
      @cache.put l
    end

    def layer_by_diff_id(h : V1::Hash)
      @cache.get h
    rescue LayerNotFound
      # Not cached, get it and write it
      l = @image.layer_by_diff_id h
      @cache.put l
    end
  end
end
