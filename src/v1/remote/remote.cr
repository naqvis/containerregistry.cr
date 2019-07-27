# Module Remote provides facilities for reading/writing v1.Images from/to a remote image registry.
module V1::Remote
  extend self
  DEFAULT_PLATFORM = V1::Platform.new(architecture: "amd64", os: "linux")

  # image provides access to remote image reference.
  def image(ref : Name::References, *options : Option) : V1::Image
    acceptable = [Types::DOCKERMANIFESTSCHEMA2,
                  Types::OCIMANIFESTSCHEMA1,
                  # We resolve these to images later.
                  Types::DOCKERMANIFESTLIST,
                  Types::OCIIMAGEINDEX]

    desc = _get(ref, acceptable, *options)
    desc.image
  end

  # delete removes the specified image reference from the remote registry.
  def delete(ref : Name::References, *options : Option) : Nil
    o = make_options(ref.registry, *options)
    scopes = [ref.scope(Transport::DELETE_SCOPE)]
    tr = Transport.new_transport(ref.as_repository.registry, o.auth, o.client, scopes)

    fetcher = Fetcher.new(ref, tr.client)
    uri = fetcher.uri("manifests", ref.identifier)
    resp = fetcher.delete(uri)
    raise "unrecognized status code during DELETE: #{resp.status}; #{resp.body}" unless resp.success?
  end

  # Index provides access to a remote index reference.
  def index(ref : Name::References, *options : Option)
    acceptable = [Types::DOCKERMANIFESTLIST, Types::OCIIMAGEINDEX]
    desc = _get(ref, acceptable, *options)
    desc.image_index
  end

  # List calls /tags/list for the given repository, returning the list of tags
  # in the "tags" property.
  def list(repo : Name::Repository, *opts : Option)
    o = make_options(repo.registry, *opts)
    tr = Transport.new_transport(
      repo.registry, o.auth, o.client, [repo.scope(Transport::PULL_SCOPE)]
    )

    fetcher = Fetcher.new(repo, tr.client)
    uri = fetcher.uri("tags", "list")

    resp = fetcher.get(uri)
    err = Transport.check_error(resp, 200)
    raise err unless err.nil?

    tags = Tags.from_json(resp.body)

    tags.tags
  end

  # Get returns a remote.Descriptor for the given reference. The response from
  # the registry is left un-interpreted, for the most part. This is useful for
  # querying what kind of artifact a reference represents.
  def get(ref : Name::References, *options : Option)
    acceptable = [Types::DOCKERMANIFESTSCHEMA2,
                  Types::OCIMANIFESTSCHEMA1,
                  Types::DOCKERMANIFESTLIST,
                  Types::OCIIMAGEINDEX,
                  # Just to look at them
                  Types::DOCKERMANIFESTSCHEMA1,
                  Types::DOCKERMANIFESTSCHEMA1SIGNED]
    _get(ref, acceptable, *options)
  end

  # write pushes the provided img to the specified image reference
  def write(ref : Name::References, img : V1::Image, *options : Option)
    ls = img.layers
    o = make_options(ref.registry, *options)
    scopes = scopes_for_uploading_image(ref, ls)
    tr = Transport.new_transport(ref.registry, o.auth, o.client, scopes)
    w = Writer.new(
      ref: ref,
      client: tr.client
    )

    # upload individual layers in fibers and collect any errors.
    # If we can dedupe by the layer digest, try to do so. If we can't determine
    # the digest for whatever reason, we can't dedupe and might re-upload.
    uploaded = ::Hash(V1::Hash, Bool).new
    g = V1::Util::Group.new

    ls.each_with_index do |l, _|
      # Streaming layers calculate their digests while uploading them. Assume
      # an error here indicates we need to upload the layer.
      begin
        h = l.digest
        if h && h != V1::Hash.empty
          # If we can determine the layer's digest ahead of time,
          # use it to dedupe uploads.
          if uploaded.has_key?(h) && uploaded[h] # already uploading
            V1::Logger.info "Skipping uploaded layer : #{h.to_s}"
            next
          end
          uploaded[h] = true
        end
      rescue
      end

      # w.upload_one(l)
      proc = ->(x : V1::Layer) do
        ->{ w.upload_one(x) }
      end

      g.spawn proc.call(l)
    end

    begin
      l = Partial.config_layer(img)
      # We *can* read the ConfigLayer, so upload it concurrently with the layers.
      # w.upload_one(l)
      proc = ->(x : V1::Layer) do
        ->{ w.upload_one(x) }
      end

      g.spawn proc.call(l)

      # Wait for the layers + config
      exc = g.wait
      raise exc unless exc.nil?
    rescue Stream::ExNotComputed
      # We can't read the ConfigLayer, possible because of streaming layers,
      # since the layer diff_ids haven't been calculated yet. Attempt to wait
      # for the other layers to be uploaded, then try the config again.

      exc = g.wait
      raise exc unless exc.nil?

      # Now that al the layers are uploaded, try to upload the config file blob.
      l = Partial.config_layer(img)
      w.upload_one(l)
    end
    # With all of the constituent elements uploaded, upload the manifest
    # to commit the image.
    w.commit_image(img)
  end

  def scopes_for_uploading_image(ref : Name::References, layers : Array(V1::Layer))
    scope_set = ::Hash(String, String).new
    layers.each_with_index do |l, _|
      if l.is_a?(V1::Remote::MountableLayer)
        ml = l.as(V1::Remote::MountableLayer)
        # we add push scope for @ref after the loop
        if ml.reference.as_repository != ref.as_repository
          scope_set[ml.reference.scope(Transport::PULL_SCOPE)] = ""
        end
      end
    end
    scopes = Array(String).new
    # Push scope should be the first element because a few registries just look at the first scope
    # to determine access.
    scopes << ref.scope(Transport::PUSH_SCOPE)
    scopes += scope_set.keys
    scopes
  end

  # write_index pushes the provided ImageIndex to the specified image reference.
  # write_index will attempt to push all of the referenced manifests before
  # attempting to push the ImageIndex, to retain referential integrity.
  def write_index(ref : Name::References, ii : V1::ImageIndex, *options : Option)
    index = ii.index_manifest
    o = make_options(ref.registry, *options)

    scopes = [ref.scope(Transport::PUSH_SCOPE)]
    tr = Transport.new_transport(ref.registry, o.auth, o.client, scopes)
    w = Writer.new(ref: ref, client: tr.client)

    index.manifests.each_with_index do |desc, _|
      ref = Name::Reference.parse_reference("#{ref.as_repository.name}@#{desc.digest.to_s}", true)
      exists = w.check_existing_manifest desc.digest, desc.media_type
      if exists
        V1::Logger.info "existing manifest: #{desc.digest.to_s}"
        next
      end

      case desc.media_type
      when Types::OCIIMAGEINDEX, Types::DOCKERMANIFESTLIST
        ii = ii.image_index(desc.digest)
        write_index(ref, ii, with_auth(o.auth)) # , with_transport(o.client))
      when Types::OCIMANIFESTSCHEMA1, Types::DOCKERMANIFESTSCHEMA2
        img = ii.image(desc.digest)
        write(ref, img, with_auth(o.auth)) # , with_transport(o.client))
      end
    end

    # With all of the constituent elements uploaded, upload the manifest
    # to commit the image.
    w.commit_image(ii)
  end

  # Handle options and fetch the manifest with the acceptable MediaTypes in th
  # Accept header.
  private def _get(ref : Name::References, acceptable : Array(Types::MediaType), *options : Option)
    o = make_options(ref.registry, *options)

    tr = Transport.new_transport(
      ref.registry, o.auth, o.client, [ref.scope(Transport::PULL_SCOPE)]
    )

    f = Fetcher.new(ref, tr.client)
    b, desc = f.fetch_manifest(ref, acceptable)

    Descriptor.new(f, desc, b, o.platform)
  end

  # method used for specs only
  protected def remote_image(fetcher)
    RemoteImage.new(fetcher)
  end
end

require "./**"
