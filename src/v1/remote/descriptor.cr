require "../platform"
require "../../name"
require "../types"
require "../manifest"
require "uri"
require "cossack"

module V1::Remote
  class Descriptor
    @fetcher : Fetcher
    @v1 : V1::Descriptor
    @manifest : Bytes

    # so we can share this implementation with Image
    @platform : V1::Platform

    getter :manifest, :platform
    delegate media_type, digest, size, to: @v1

    def initialize(@fetcher, @v1, @manifest, @platform)
    end

    # Image converts the Descriptor into a v1.Image.
    #
    # If the fetched artifact is already an image, it will just return it.
    #
    # If the fetched artifact is an index, it will attempt to resolve the index to
    # a child image with the appropriate platform.
    #
    # See WithPlatform to set the desired platform.
    def image
      case @v1.media_type
      when Types::DOCKERMANIFESTSCHEMA1, Types::DOCKERMANIFESTSCHEMA1SIGNED
        # We don't care to support schema 1 images:
        raise "unsupported media type : #{@v1.media_type.to_s}"
      when Types::OCIIMAGEINDEX, Types::DOCKERMANIFESTLIST
        # We want an image but the registry has an index, resolve it to an image
        return remote_index.image_by_platform(@platform)
      when Types::OCIMANIFESTSCHEMA1, Types::DOCKERMANIFESTSCHEMA2
        # These are expected, Enumerated here to follow a default case
      else
        # We could just return an error here,but some registries (e.g. static
        # registries) don't set the Content-Type headers correctly, so instead...
        # Log a warning
        V1::Logger.info "unhandled media type : #{@v1.media_type.to_s}"
      end

      # Wrap the v1.Layers returned by this v1.Image in a hint for downstream
      # remote.Write calls to facilitate cross-repo "mounting".

      img_core = V1::Partial.compressed_to_image(remote_image)
      MountableImage.new(image: img_core, reference: @fetcher.ref)
    end

    # ImageIndex converts the Descriptor into a v1.ImageIndex.
    def image_index
      case @v1.media_type
      when Types::DOCKERMANIFESTSCHEMA1, Types::DOCKERMANIFESTSCHEMA1SIGNED
        # We don't care to support schema 1 images:
        raise "unsupported media type : #{@v1.media_type.to_s}"
      when Types::OCIMANIFESTSCHEMA1, Types::DOCKERMANIFESTSCHEMA2
        # We want an index but the registry has an image, nothing we can do.
        raise "unexpected media type for image_index: #{@v1.media_type.to_s}; call image instead."
      when Types::OCIIMAGEINDEX, Types::DOCKERMANIFESTLIST
        # These are expected
      else
        # We could just return an error here,but some registries (e.g. static
        # registries) don't set the Content-Type headers correctly, so instead...
        # Log a warning
        V1::Logger.info "unhandled media type : #{@v1.media_type.to_s}"
      end

      remote_index
    end

    def remote_image
      f = Fetcher.new(@fetcher.ref, @fetcher.client)
      RemoteImage.new(fetcher: f, manifest: @manifest, media_type: @v1.media_type)
    end

    def remote_index
      f = Fetcher.new(@fetcher.ref, @fetcher.client)
      RemoteIndex.new(fetcher: f, manifest: @manifest, media_type: @v1.media_type)
    end
  end

  private class Fetcher
    @ref : Name::References
    @client : Cossack::Client
    getter :ref, :client

    def initialize(@ref, @client)
    end

    private def parse_reg
      s = "#{ref.registry.scheme}://#{ref.registry.reg_name}"
      u = URI.parse(s)
      {u.host, u.port}
    end

    # returns a URI for the specified path in the context of this remote image reference.
    def uri(resource, identifier)
      host, port = parse_reg
      URI.new(scheme: ref.registry.scheme,
        host: host,
        port: port,
        path: "/v2/#{ref.repo_str}/#{resource}/#{identifier}")
    end

    def get(uri : URI, headers : HTTP::Headers = HTTP::Headers.new)
      request = Cossack::Request.new(method: "GET", uri: uri, headers: headers)
      client.call(request)
    end

    def delete(uri : URI, headers : HTTP::Headers = HTTP::Headers.new)
      request = Cossack::Request.new(method: "DELETE", uri: uri, headers: headers)
      client.call(request)
    end

    def fetch_manifest(ref : Name::References, acceptable : Array(Types::MediaType))
      uri = uri("manifests", ref.identifier)
      accept = [] of String
      acceptable.each do |mt|
        accept << mt.to_s
      end
      headers = HTTP::Headers{"Accept" => accept.join(",")}
      # request = Cossack::Request.new(method: "GET", uri: uri, headers: headers)
      # resp = client.call(request)
      resp = get(uri, headers)
      err = Transport.check_error(resp, 200)
      raise err unless err.nil?

      digest, size = V1::Hash.sha256(IO::Memory.new(resp.body))
      mt = resp.headers["Content-Type"]?
      mt = mt.nil? ? "" : mt
      media_type = Types::MediaType[mt]

      # Validate the digest matches what we asked for, if pulling by digest.
      if dgst = ref.as?(Name::Digest)
        if media_type == Types::DOCKERMANIFESTSCHEMA1SIGNED
          # Digests for this are stupid to calculate, ignore it.
        elsif digest.to_s != dgst.digest
          raise "manifest digest: #{digest.to_s} does not match requested digest: #{dgst.digest}"
        end
      else
        # Do nothing for tags; I give up.
        #
        # We'd like to validate that the "Docker-Content-Digest" header matches what is returned by the registry,
        # but so many registries implement this incorrectly that it's not worth checking.
        #
        # For reference:
        # https:#github.com/docker/distribution/issues/2395
        # https:#github.com/GoogleContainerTools/kaniko/issues/298
      end

      # Return all this info since we have to calculate it anyway.
      desc = V1::Descriptor.new(media_type, digest, size)
      {resp.body.to_slice, desc}
    end
  end
end
