module V1::Remote
  # RemoteImage accesses an image from a remote registry
  private class RemoteImage
    include V1::Partial::CompressedImageCore
    include V1::Partial::WithRawManifest
    include V1::Partial::WithRawConfigFile

    getter fetcher : Fetcher
    @manifest_lock : Mutex # protects manifest
    @manifest : Bytes
    @config_lock : Mutex # protects config
    @config : Bytes
    @media_type : Types::MediaType

    def initialize(@fetcher, @manifest, @media_type, @config = Bytes.empty)
      @manifest_lock = Mutex.new
      @config_lock = Mutex.new
    end

    protected def initialize(@fetcher)
      initialize(@fetcher, Bytes.empty, Types::MediaType[""])
    end

    def media_type
      return @media_type unless @media_type.to_s.blank?
      Types::DOCKERMANIFESTSCHEMA2
    end

    def raw_manifest
      @manifest_lock.synchronize {
        return @manifest if @manifest != Bytes.empty

        # We should never get here because the public entrypoints
        # do type-checking via Remote::Descriptor. I've left this here for tests that
        # directly instantiate a RemoteImage

        acceptable = [Types::DOCKERMANIFESTSCHEMA2, Types::OCIMANIFESTSCHEMA1]
        manifest, desc = @fetcher.fetch_manifest(@fetcher.ref, acceptable)
        @media_type = desc.media_type
        @manifest = manifest
        @manifest
      }
    end

    def raw_config_file
      @config_lock.lock
      return @config if @config && !@config.empty?

      m = V1::Partial.manifest(self)
      cl = layer_by_digest(m.config.digest)
      body = cl.compressed
      @config = V1::Util.read_all(body)
      body.close
      @config
    ensure
      @config_lock.unlock
    end

    # implements Partial::CompressedLayer
    def layer_by_digest(h : V1::Hash) : V1::Partial::CompressedLayer
      RemoteLayer.new ri: self, digest: h
    end
  end

  # implements partial.CompressedLayer
  private class RemoteLayer
    # include V1::Layer
    include V1::Partial::CompressedLayer
    include V1::Partial::WithManifestAndConfigFile
    include V1::Partial::WithDiffID
    include V1::Partial::WithManifest
    include V1::Partial::WithRawManifest

    @ri : RemoteImage
    @digest : V1::Hash

    # delegate raw_manifest, uncompressed, to: @ri
    delegate raw_manifest, to: @ri

    def initialize(@ri, @digest)
    end

    # implements Partial::CompressedLayer
    def digest
      @digest
    end

    # implements Partial::CompressedLayer
    def compressed
      u = @ri.fetcher.uri("blobs", @digest.to_s)
      resp = @ri.fetcher.client.get(u.to_s)
      err = Transport.check_error(resp, 200)
      raise err unless err.nil?

      V1::Util.verify_read_closer(IO::Memory.new(resp.body), @digest)
    end

    # manifest implements Partial::WithManifest so that we can use Partial.blob_size below
    def manifest
      V1::Partial.manifest(@ri)
    end

    # implements V1::Layer
    def media_type
      m = manifest
      m.layers.each_with_index do |l, _|
        return l.media_type if l.digest == @digest
      end
      raise "unable to find layer with digest: #{@digest}"
    end

    # implements Partial::CompressedLayer
    def size
      # Look up the size of this digest in the manifest to avoid a request.
      V1::Partial.blob_size(self, @digest)
    end

    # config_file implements Partial::WithManifestAndConfigFile so that we can use partial.BlobToDiffID below.
    def config_file
      V1::Partial.config_file(@ri)
    end

    # diff_id implements Partial::WithDiffID so that we don't recompute a DiffID that we already have
    # available in our ConfigFile
    def diff_id
      V1::Partial.blob_to_diff_id(self, @digest)
    end
  end
end
