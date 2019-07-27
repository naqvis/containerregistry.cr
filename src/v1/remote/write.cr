require "cossack"

module V1::Remote
  module Manifest
    abstract def raw_manifest : Bytes
    abstract def media_type : Types::MediaType
    abstract def digest : V1::Hash
  end

  # Writer writes the element of an image to a remote image reference.
  private class Writer
    @ref : Name::References
    @client : Cossack::Client

    def initialize(@ref, @client)
    end

    def initialize(@ref)
      @client = Cossack::Client.new
    end

    private def parse_reg
      s = "#{@ref.registry.scheme}://#{@ref.registry.reg_name}"
      u = URI.parse(s)
      {u.host, u.port}
    end

    # url returns a URI for the specified path in the context of this remote image reference.
    def url(path : String)
      h, p = parse_reg
      URI.new(scheme: @ref.scheme, host: h, port: p, path: path)
    end

    # next_location extracts the fully-qualified URL to which we should send the next request in an upload sequence.
    def next_location(resp : Cossack::Response)
      loc = resp.headers.fetch("Location", "")
      raise "missing Location header" if loc.blank?

      u = URI.parse(loc)

      # If the location header returned is just a url path, then fully qualify it.
      # We cannot simply call `#url`, since there might be an embedded query string.
      if u.host.nil? || ((h = u.host) && h.blank?)
        h, p = parse_reg
        u.host = h
        u.port = p
      end
      if u.scheme.nil? || ((s = u.scheme) && s.blank?)
        u.scheme = @ref.scheme
      end
      u
    end

    # check_existing_blob checks if a blob exists already in the repository by making a
    # HEAD request to the blob store API.  GCR performs an existence check on the
    # initiation if "mount" is specified, even if no "from" sources are specified.
    # However, this is not broadly applicable to all registries, e.g. ECR.
    def check_existing_blob(h : V1::Hash)
      u = url sprintf("/v2/%s/blobs/%s", @ref.repo_str, h.to_s)
      resp = @client.head u.to_s
      err = Transport.check_error(resp, 200, 404)
      raise err unless err.nil?

      resp.status == 200
    end

    # check_existing_manifest checks if a manifest exists already in the repository
    # by making a HEAD request to the manifest API.
    def check_existing_manifest(h : V1::Hash, mt : Types::MediaType)
      u = url sprintf("/v2/%s/manifests/%s", @ref.repo_str, h.to_s)
      request = Cossack::Request.new(method: "HEAD", uri: u,
        headers: HTTP::Headers{"Accept" => mt.to_s})
      resp = @client.call request
      err = Transport.check_error(resp, 200, 404)
      raise err unless err.nil?
      resp.status == 200
    end

    # initiate_upload initiates the blob upload, which starts with a POST that can
    # optionally include the hash of the layer and a list of repositories from
    # which that layer might be read. On failure, an error is returned.
    # On success, the layer was either mounted (nothing more to do) or a blob
    # upload was initiated and the body of that blob should be sent to the returned
    # location.
    def initiate_upload(from : String, mount : String)
      u = url sprintf("/v2/%s/blobs/uploads/", @ref.repo_str)
      if !from.blank? && !mount.blank?
        u.query = HTTP::Params.encode(::Hash{
          "mount" => mount,
          "from"  => from,
        })
      end

      # Make the request to initiate the blob upload
      resp = @client.post(u.to_s) do |req|
        req.headers["Content-Type"] = "application/json"
      end
      err = Transport.check_error(resp, 201, 202)
      raise err unless err.nil?

      case resp.status
      when 201 # Created
        # We're done, we were able to fast-path
        {"", true}
      when 202 # Accepted
        # Proceed to PATCH, upload has begun.
        loc = next_location(resp)
        {loc.to_s, false}
      else
        raise "Unreachable: initiate_upload"
      end
    end

    # stream_blob streams the contents of the blob to the specified location.
    # On failure, this will return an error.  On success, this will return the location
    # header indicating how to commit the streamed blob.
    def stream_blob(blob : IO, stream_location : String)
      resp = @client.patch(stream_location, blob) do |req|
        req.headers.each { |k, _| req.headers.delete(k) }
      end
      err = Transport.check_error(resp, 204, 202, 201)
      raise err unless err.nil?

      # The blob has been uploaded, return the location header indicating
      # how to commit this layer.
      next_location resp
    ensure
      blob.close
    end

    # commit_blob commits this blob by sending a PUT to the location returned from
    # streaming the blob.
    def commit_blob(location : String, digest : String)
      u = URI.parse(location)
      if (query = u.query)
        v = HTTP::Params.parse(query)
      else
        v = HTTP::Params.new
      end
      v["digest"] = digest
      u.query = v.to_s
      resp = @client.put(u.to_s) do |req|
        req.headers.delete("Content-Type") if req.headers.has_key?("Content-Type")
      end
      err = Transport.check_error(resp, 201)
      raise err unless err.nil?
    end

    # upload_one performs a complete upload of a single layer.
    def upload_one(l : V1::Layer) : Nil
      from = mount = ""
      begin
        h = l.digest
        # If we know the digest, this isn't a streaming layer. Do an existence
        # check so we can skip uploading the layer if possible
        existing = check_existing_blob(h)
        if existing
          V1::Logger.info "existing blob #{h.to_s}"
          return
        end
        mount = h.to_s
      rescue ex
      end

      if l.is_a?(V1::Remote::MountableLayer)
        ml = l.as(V1::Remote::MountableLayer)
        if @ref.reg_name == ml.reference.reg_name
          from = ml.reference.repo_str
        end
      end
      max_retries = 2
      back_off_factor = 0.5
      retries = 0
      loop do
        try_upload(l, from, mount)
        return
      rescue ex
        if (m = ex.message) && m.includes?("BLOB_UPLOAD_INVALID")
          raise ex if retries >= max_retries
          V1::Logger.info "retrying after error: #{ex.message}"
          retries += 1
          duration = back_off_factor * (2**retries) # in seconds
          sleep(duration)
        else
          raise ex
        end
      end
    end

    # commit_image does a PUT of the image's manifest
    def commit_image(man)
      raw = man.raw_manifest
      if raw.nil?
        raise "unable to get raw_manifest"
      end
      mt = man.media_type
      u = url sprintf("/v2/%s/manifests/%s", @ref.repo_str, @ref.identifier)
      # Make the request to PUT the serialized manifest
      resp = @client.put(u.to_s, String.new(raw)) do |req|
        req.headers["Content-Type"] = mt.to_s
      end
      err = Transport.check_error(resp, 200, 201, 202)
      raise err unless err.nil?

      digest = man.digest

      # The image was successfully pushed!
      V1::Logger.info "#{@ref.to_s}: digest: #{digest.to_s} size: #{raw.size}"
    end

    private def try_upload(l, from, mount)
      loc, mounted = initiate_upload(from, mount)
      if mounted
        h = l.digest
        V1::Logger.info "mounted blob: #{h.to_s}"
        return
      end

      blob = l.compressed
      location = stream_blob(blob, loc)
      h = l.digest
      digest = h.to_s
      commit_blob(location.to_s, digest)
      V1::Logger.info "pushed blob: #{digest}"
    end
  end
end
