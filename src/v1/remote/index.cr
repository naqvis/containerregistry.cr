require "mutex"
require "./write"

module V1::Remote
  # Index provides access to a remote index reference.
  private class RemoteIndex
    include Manifest
    include V1::Partial::WithRawManifest
    include V1::ImageIndex
    @fetcher : Fetcher
    @manifest_lock : Mutex
    @manifest : Bytes
    @media_type : Types::MediaType

    getter :fetcher, :manifest

    def initialize(@fetcher, @manifest = Bytes.empty, @media_type = Types::DOCKERMANIFESTLIST)
      @manifest_lock = Mutex.new
    end

    def media_type
      return @media_type unless @media_type.to_s.empty?
      Types::DOCKERMANIFESTLIST
    end

    def digest
      V1::Partial.digest(self)
    end

    def raw_manifest
      @manifest_lock.lock
      return @manifest unless @manifest.size == 0

      # We should never get here because the public entrypoints
      # do type-checking via Remote::Descriptor. I've left this here for
      # tests that directly instantiate a RemoteIndex
      acceptable = [
        Types::DOCKERMANIFESTLIST,
        Types::OCIIMAGEINDEX,
      ]
      manifest, desc = fetcher.fetch_manifest(fetcher.ref, acceptable)
      @media_type = desc.media_type
      @manifest = manifest
      @manifest
    ensure
      @manifest_lock.unlock
    end

    def index_manifest
      b = raw_manifest
      V1.parse_index_manifest(IO::Memory.new(b, writeable: false))
    end

    def image(h : V1::Hash)
      desc = child_by_hash(h)
      # Descriptor.Image will handle coercing nested indexes into an Image.
      desc.image
    end

    def image_index(h : V1::Hash)
      desc = child_by_hash(h)
      desc.image_index
    end

    def image_by_platform(platform : V1::Platform)
      desc = child_by_platform(platform)
      # Descriptor.image will handle coercing nested indexes into an Image.
      desc.image
    end

    # This naively matches the first manifest with matching Architecture and OS.
    def child_by_platform(platform : V1::Platform)
      index = index_manifest
      index.manifests.each_with_index do |c, _|
        # If platform is missing from child descriptor, assume it's amd64/linux.
        p = c.platform ? c.platform : DEFAULT_PLATFORM
        return child_descriptor(c, p) if (platform.architecture == p.architecture && platform.os == p.os)
      end
      raise "no child with platform #{platform.architecture}/#{platform.os} in index #{fetcher.ref.to_s}"
    end

    def child_by_hash(h : V1::Hash)
      index = index_manifest
      index.manifests.each_with_index do |c, _|
        return child_descriptor(c, DEFAULT_PLATFORM) if h == c.digest
      end
      raise "no child with digest #{h.to_s} in index #{fetcher.ref.to_s}"
    end

    def child_ref(h : V1::Hash)
      Name::Reference.parse_reference "#{fetcher.ref.name}@#{h.to_s}"
    end

    # Convert one of this index's child's v1.Descriptor into a remote.Descriptor, with the given platform option.
    def child_descriptor(child : V1::Descriptor, platform : V1::Platform)
      ref = child_ref(child.digest)
      manifest, desc = fetcher.fetch_manifest(ref, [child.media_type])
      Descriptor.new(fetcher: Fetcher.new(ref: ref, client: fetcher.client),
        v1: desc, manifest: manifest, platform: platform)
    end
  end
end
