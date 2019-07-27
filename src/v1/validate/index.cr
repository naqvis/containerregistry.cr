module V1::Validator
  extend self

  # validates that idx does not violate any invariants of the index format.
  protected def index(idx : V1::ImageIndex)
    errs = Array(String).new
    if (err = validate_children(idx)) && !err.blank?
      errs << "validating children: #{err}"
    end
    if (err = validate_index_manifest(idx)) && !err.blank?
      errs << "validating index manifest: #{err}"
    end
    raise errs.join("\n\n") if errs.size > 0
  end

  private def validate_children(idx)
    begin
      manifest = idx.index_manifest
      errs = Array(String).new
      manifest.manifests.each_with_index do |desc, i|
        case desc.media_type
        when Types::OCIIMAGEINDEX, Types::DOCKERMANIFESTLIST
          idx = idx.image_index(desc.digest)
          begin
            index idx
          rescue ex
            errs << sprintf("failed to validate index manifests[%d](%s): %s", i, desc.digest.to_s, ex.message)
          end
        when Types::OCIMANIFESTSCHEMA1, Types::DOCKERMANIFESTSCHEMA2
          img = idx.image(desc.digest)
          begin
            image(img)
          rescue ex
            errs << sprintf("failed to validate image manifests[%d](%s): %s", i, desc.digest.to_s, ex.message)
          end
        else
          raise "todo: validate index blob()"
        end
      end
      raise errs.join("\n\n") if errs.size > 0
    rescue ex
      return ex.message
    end
    ""
  end

  private def validate_index_manifest(idx)
    begin
      digest = idx.digest
      rm = idx.raw_manifest
      if rm.nil?
        raise "unable to get index raw_manifest"
      else
        hash, _ = V1::Hash.sha256(IO::Memory.new rm)
        m = idx.index_manifest
        pm = V1.parse_index_manifest IO::Memory.new rm
        errs = Array(String).new
        if digest != hash
          errs << sprintf("mismatched manifest digest: Digest()=%s, SHA256(RawManifest())=%s", digest, hash)
        end

        if pm != m
          errs << "mismatched manifest content"
        end
        raise errs.join("\n\n") if errs.size > 0
      end
    rescue ex
      return ex.message
    end
    ""
  end
end
