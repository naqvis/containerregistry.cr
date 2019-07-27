module V1::Validator
  extend self

  # validates that img does not violate any invariants of the image format.
  protected def image(img : V1::Image)
    errs = Array(String).new
    if (err = validate_layers(img)) && !err.blank?
      errs << "validating layers: #{err}"
    end
    if (err = validate_config(img)) && !err.blank?
      errs << "validating config: #{err}"
    end
    if (err = validate_manifest(img)) && !err.blank?
      errs << "validating manifest: #{err}"
    end
    raise errs.join("\n\n") if errs.size > 0
  end

  private def validate_config(img)
    begin
      cn = img.config_name
      rc = img.raw_config_file
      h, s = V1::Hash.sha256(IO::Memory.new rc)
      m = img.manifest
      cf = img.config_file
      pcf = V1.parse_config_file(IO::Memory.new rc)
      errs = Array(String).new
      if cn != h
        errs << "mismatched config digest: config_name()=#{cn.to_s}, sha256(raw_config_file())=#{h.to_s}"
      end
      want, got = m.try(&.config.size), s
      if want != got
        errs << "mismatched config size: manifest.config.size()=#{want}, raw_config_file.size()=#{got}"
      end
      if pcf != cf
        errs << "mismatched config content"
      end
      if cf.try(&.rootfs.type) != "layers"
        errs << "invalid config_file.rootfs.type: #{cf.try(&.rootfs.type)} != layers"
      end
      raise errs.join("\n") if errs.size > 0
    rescue ex
      return ex.message
    end
    ""
  end

  private def validate_layers(img)
    begin
      layers = img.layers
      digests = Array(V1::Hash).new
      diff_ids = Array(V1::Hash).new
      sizes = Array(Int64).new
      layers.each do |layer|
        # TODO: Test layer.uncompressed
        compressed = layer.compressed
        # Keep track of compressed digest.
        digester = V1::Hash.hasher "sha256"
        # Everything read from compressed is written to digester to compute digest
        hash_compressed = V1::Util::TeeReader.new(compressed, digester)

        # Call IO.copy to write from the layer IO through to the Crystar::Reader on
        # the other side of the pipe.
        pr, pw = IO.pipe
        size = 0_i64

        proc = ->(w : IO, c : IO) {
          spawn do
            size += IO.copy c, w
            # Now close the compressed reader, to flush the gzip stream
            # and calculate digest/diffID/size. This will cause pr to
            # return EOF which will cause readers of the Compressed stream
            # to finish reading.
            c.close
            w.close
          end
        }
        proc.call(pw, hash_compressed)
        Fiber.yield

        # Read the bytes through Gzip::Reader to compute the diff_id
        uncompressed = Gzip::Reader.new(pr)
        diff_ider = V1::Hash.hasher "sha256"
        hash_uncompressed = V1::Util::TeeReader.new(uncompressed, diff_ider)

        # Ensure there aren't duplicate file paths.
        Crystar::Reader.open(hash_uncompressed) do |tr|
          files = ::Hash(String, String).new
          tr.each_entry do |hdr|
            raise "duplicate file path: #{hdr.name}" if files.has_key?(hdr.name)
            files[hdr.name] = ""
          end
        end

        # Discard any trailing padding that the tar.Reader doesn't consume.
        _ = V1::Util.read_all(hash_uncompressed)
        uncompressed.close
        digest = V1::Hash.new("sha256", digester.digest.hexstring)
        diff_id = V1::Hash.new("sha256", diff_ider.digest.hexstring)

        # compute all of these first before we call config() and manifest() to allow
        # for lazy access e.g. for Stream::Layer
        digests << digest
        diff_ids << diff_id
        sizes << size
      end
      cf = img.config_file
      m = img.manifest
      errs = Array(String).new
      layers.each_with_index do |layer, i|
        digest = layer.digest
        diff_id = layer.diff_id
        size = layer.size
        if digest != digests[i]
          errs << "mismatched layer[#{i}] digest: digest()=#{digest.to_s}, sha256(compressed())=#{digests[i].to_s}"
        end
        if m.try(&.layers.try(&.[i].digest)) != digests[i]
          errs << "mismatched layer[#{i}] digest: digest()= manifest.layers[#{i}].digest = #{m.try(&.layers.try(&.[i].digest)).to_s}, sha256(compressed())=#{digests[i].to_s}"
        end

        if diff_id != diff_ids[i]
          errs << sprintf("mismatched layer[%d] diffid: DiffID()=%s, sha256(Gunzip(Compressed()))=%s", i, diff_id, diff_ids[i])
        end

        if cf.try(&.rootfs.diff_ids[i]) != diff_ids[i]
          errs << sprintf("mismatched layer[%d] diffid: config_file.rootfs.diff_ids[%d]=%s, sha256(Gunzip(Compressed()))=%s", i, i, cf.try(&.rootfs.diff_ids[i]), diff_ids[i])
        end

        if size != sizes[i]
          errs << sprintf("mismatched layer[%d] size: Size()=%d, len(Compressed())=%d", i, size, sizes[i])
        end

        if m.try(&.layers.try(&.[i].size)) != sizes[i]
          errs << sprintf("mismatched layer[%d] size: Manifest.Layers[%d].Size=%d, len(Compressed())=%d", i, i, m.try(&.layers.try(&.[i].size)), sizes[i])
        end
      end
      raise errs.join("\n") if errs.size > 0
    rescue ex
      return ex.message
    end
    ""
  end

  private def validate_manifest(img)
    begin
      digest = img.digest
      rm = img.raw_manifest
      if rm.nil?
        raise "unable to get raw_manifest"
      else
        hash, _ = V1::Hash.sha256(IO::Memory.new rm)
        m = img.manifest
        pm = V1.parse_manifest(IO::Memory.new rm)
        errs = Array(String).new
        if digest != hash
          errs << sprintf("mismatched manifest digest: Digest()=%s, SHA256(RawManifest())=%s", digest, hash)
        end
        if pm != m
          errs << "mismatched manifest content"
        end
        raise errs.join("\n") if errs.size > 0
      end
    rescue ex
      return ex.message
    end
    ""
  end
end
