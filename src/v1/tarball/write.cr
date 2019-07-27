require "crystar"

module V1::Tarball
  extend self

  # write_to_file writes in the compressed format to a tarball, on disk.
  # This is just syntactic sugar wrapping tarball.Write with a new file.
  def write_to_file(path : String, ref : Name::References, img : V1::Image)
    File.open(path, "w") do |f|
      write ref, img, f
    end
  end

  # multi_write_to_file writes in the compressed format to a tarball, on disk.
  # This is just syntactic sugar wrapping tarball.MultiWrite with a new file.
  def multi_write_to_file(path : String, tag_to_image : ::Hash(Name::Hash, V1::Image))
    ref_to_image = Hash(Name::References, V1::Image).new tag_to_image.size
    tag_to_image.each do |k, v|
      ref_to_image[k] = v
    end
    multi_ref_write_to_file path, ref_to_image
  end

  # multi_ref_write_to_file writes in the compressed format to a tarball, on disk.
  # This is just syntactic sugar wrapping tarball.MultiRefWrite with a new file.
  def multi_ref_write_to_file(path : String, ref_to_image : ::Hash(Name::References, V1::Image))
    File.open(path, "w") do |f|
      multi_ref_write ref_to_image, f
    end
  end

  # Write is a wrapper to write a single image and tag to a tarball.
  def write(ref : Name::References, img : V1::Image, w : IO)
    multi_ref_write ::Hash{ref => img}, w
  end

  # multi_write writes the contents of each image to the provided reader, in the compressed format.
  # The contents are written in the following format:
  # One manifest.json file at the top level containing information about several images.
  # One file for each layer, named after the layer's SHA.
  # One file for the config blob, named after its SHA.
  def multi_write(tag_to_image : ::Hash(Name::Tag, V1::Image), w : IO)
    ref_to_image = ::Hash(Name::References, V1::Image).new tag_to_image.size
    tag_to_image.each do |k, v|
      ref_to_image[k] = v
    end
    multi_ref_write ref_to_image, w
  end

  # multi_ref_write writes the contents of each image to the provided reader, in the compressed format.
  # The contents are written in the following format:
  # One manifest.json file at the top level containing information about several images.
  # One file for each layer, named after the layer's SHA.
  # One file for the config blob, named after its SHA.
  def multi_ref_write(ref_to_image : ::Hash(Name::References, V1::Image), w : IO)
    Crystar::Writer.open(w) do |tf|
      image_to_tags = dedup_ref_to_image ref_to_image
      td = TarDescriptor.new image_to_tags.size
      image_to_tags.each do |img, tags|
        cfg_name = img.config_name
        cfg_blob = img.raw_config_file
        write_tar_entry tf, cfg_name.to_s, IO::Memory.new(cfg_blob), cfg_blob.size.to_i64

        # write the layers
        layers = img.layers
        layer_files = Array(String).new layers.size
        layers.each_with_index do |l, _|
          d = l.digest
          # Munge the file name to appease ancient technology.
          #
          # tar assumes anything with a colon is a remote tape drive:
          # https:#www.gnu.org/software/tar/manual/html_section/tar_45.html
          # Drop the algorithm prefix, e.g. "sha256:"
          hex = d.hex

          # gunzip expects certain file extensions:
          # https:#www.gnu.org/software/gzip/manual/html_node/Overview.html
          layer_files << "#{hex}.tar.gz"

          r = l.compressed
          blob_size = l.size
          write_tar_entry tf, layer_files[layer_files.size - 1], r, blob_size
        end

        # Generate the tar descriptor and write to it
        sitd = SingleImageTarDescriptor.new(
          config: cfg_name.to_s,
          repo_tags: tags,
          layers: layer_files
        )
        td << sitd
      end
      td_bytes = td.to_json
      write_tar_entry tf, "manifest.json", IO::Memory.new(td_bytes), td_bytes.size.to_i64
    end
  end

  def dedup_ref_to_image(ref_to_image : ::Hash(Name::References, V1::Image))
    image_to_tags = ::Hash(V1::Image, Array(String)).new

    ref_to_image.each do |ref, img|
      if ref.is_a?(Name::Tag)
        tag = ref.as(Name::Tag)
        if image_to_tags.has_key?(img)
          tags = image_to_tags[img]
          image_to_tags[img] = tags << tag.to_s
        else
          image_to_tags[img] = [tag.to_s]
        end
      else
        image_to_tags[img] = [] of String if !image_to_tags.has_key?(img)
      end
    end
    image_to_tags
  end

  # write a file to the provided writer with a corresponding tar header
  def write_tar_entry(tf : Crystar::Writer, path : String, r : IO, size : Int64)
    hdr = Crystar::Header.new(
      mode: 0o644_i64,
      flag: Crystar::REG.ord.to_u8,
      size: size,
      name: path
    )
    tf.write_header hdr
    tf.write V1::Util.read_all(r).to_slice
  end
end
