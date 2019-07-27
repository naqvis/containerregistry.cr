require "crystar"
require "../empty"

# Module provides facilities for mutating v1.Images of any kind.
module V1::Mutate
  extend self
  WHITEOUT_PREFIX = ".wh."

  # Addendum contains layers and history to be appended to a base image
  record Addendum, layer : V1::Layer, history : V1::History? = nil

  # append_layers applies layers to a base image
  def append_layers(base : V1::Image, layers : Array(V1::Layer))
    additions = Array(Addendum).new(layers.size)
    layers.each { |l| additions << Addendum.new layer: l }
    append base, additions
  end

  # append will apply the list of Addendum to the base image
  def append(base : V1::Image, adds : Array(Addendum))
    return base unless adds.size > 0

    validate adds
    Image.new(
      base: base,
      adds: adds
    )
  end

  # config mutates the provided V1::Image to have the provided V1::Config
  def config(base : V1::Image, cfg : V1::Config)
    cf = base.config_file
    cf.config = cfg
    config_file(base, cf)
  end

  # config_file mutates the provided V1::Image to have the provided V1::ConfigFile
  def config_file(base : V1::Image, cfg : V1::ConfigFile)
    m = base.manifest
    Image.new(
      base: base,
      manifest: m,
      config_file: cfg
    )
  end

  # created_at mutates the provided V1::Image to have the provided Time
  def created_at(base : V1::Image, created : Time)
    cf = base.config_file
    cfg = cf.dup
    cfg.created = created
    config_file(base, cfg)
  end

  def validate(adds : Array(Addendum)) : Nil
    adds.each do |add|
      raise "Unable to add a nil layer to the image" if add.layer.nil?
    end
  end

  # extract takes an image and returns an io.ReadCloser containing the image's
  # flattened filesystem.
  #
  # Callers can read the filesystem contents by passing the reader to
  # Crystar::Reader, or io.Copy it directly to some output.
  #
  # If a caller doesn't read the full contents, they should Close it to free up
  # resources used during extraction.
  #
  # Adapted from https:#github.com/google/containerregistry/blob/master/client/v2_2/docker_image_.py#L731
  def extract(img : V1::Image)
    pr, pw = IO.pipe
    spawn do
      # Close the writer with any errors encountered during
      # extraction. These errors will be returned by the reader end
      # on subsequent reads. If err == nil, the reader will return
      # EOF.
      extract img, pw
      pw.close
    end
    pr
  end

  def extract(img : V1::Image, w : IO) : Nil
    Crystar::Writer.open(w) do |tw|
      file_map = ::Hash(String, Bool).new
      layers = img.layers
      # we iterate through the layers in reverse order because it makes handling
      # whiteout layers more efficient, since we can just keep track of the removed
      # files as we see .wh. layers and ignore those in previous layers.
      (layers.size - 1).downto(0) do |i|
        layer = layers[i]
        layer_reader = layer.uncompressed
        Crystar::Reader.open(layer_reader) do |tr|
          tr.each_entry do |hdr|
            basename = Path[hdr.name].basename
            dirname = Path[hdr.name].dirname
            tombstone = basename.starts_with?(WHITEOUT_PREFIX)
            basename = basename[WHITEOUT_PREFIX.size..] if tombstone

            # check if we have seen value before
            # if we're checking a directory, don't join name
            name = hdr.flag.chr == Crystar::DIR ? hdr.name : Path[dirname].join(basename).to_s
            next if file_map.has_key?(name)

            # check for a whited out parent directory
            next if in_whiteout_dir(file_map, name)

            # mark file as handled. non-directory implicitly tombstones any entries with matching (or child) name
            file_map[name] = tombstone || !(hdr.flag.chr == Crystar::DIR)
            if !tombstone
              tw.write_header hdr
              tw.write V1::Util.read_all(hdr.io) if hdr.size > 0
            end
          end
        end
      end
    end
  end

  def in_whiteout_dir(map : ::Hash(String, Bool), file : String)
    loop do
      break if file.blank?
      dirname = Path[file].dirname
      break if file == dirname
      return true if (map.has_key?(dirname) && map[dirname])
      file = dirname
    end
    false
  end

  # time sets all timestamps in an image to the given timestamp.
  def time(img : V1::Image, t : Time)
    new_image = Empty::IMAGE
    layers = img.layers

    # Strip away all timestamps from layers
    new_layers = Array(V1::Layer).new
    layers.each do |layer|
      new_layer = layer_time layer, t
      new_layers << new_layer
    end

    new_image = append_layers new_image, new_layers

    ocf = img.config_file
    if ocf.nil?
      raise "Unable to get config file of image"
    else
      cf = new_image.config_file
      if !cf.nil?
        cfg = cf.dup

        # copy basic config over
        if !ocf.config.nil?
          cfg.config = ocf.config
        end
        if !ocf.container_config.nil?
          cfg.container_config = ocf.container_config
        end

        # Strip away timestamps from the config file

        cfg.created = t
        cfg.history.try(&.each { |h| h.created = t })

        config_file new_image, cfg
      end
    end
  end

  def layer_time(layer : V1::Layer, t : Time)
    lr = layer.uncompressed
    w = IO::Memory.new
    Crystar::Writer.open(w) do |tw|
      Crystar::Reader.open(lr) do |tr|
        tr.each_entry do |hdr|
          hdr.mod_time = t
          tw.write_header hdr
          tw.write V1::Util.read_all(hdr.io) if hdr.flag.chr == Crystar::REG
        end
      end
    end
    b = w.to_slice
    # gzip the contents, then create the layer
    opener = Proc(IO).new {
      V1::Util.gzip_reader_closer(V1::Util::NoOpCloser.new(IO::Memory.new(b)))
    }

    layer = Tarball::Layer.from_opener(opener)
    layer
  end

  # canonical is a helper function to combine Time and configFile
  # to remove any randomness during a docker build.
  def canonical(img : V1::Image)
    # Set all timestamps to 0
    created = Time.unix(0).shift(0, 0)
    img = time img, created
    cf = img.config_file

    # Get rid of host-dependent random config
    cfg = cf.dup
    cfg.container = ""
    cfg.config.hostname = ""
    cfg.container_config.hostname = ""
    cfg.docker_version = ""
    config_file img, cfg
  end
end

require "./*"
