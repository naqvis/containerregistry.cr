module V1::Partial
  extend self

  # WithRawConfigFile defines the subset of v1.Image used by these helper methods
  module WithRawConfigFile
    # returns the serialized bytes of this image's config file.
    abstract def raw_config_file : Bytes
  end

  # config_file is a helper for implementing v1 image
  def config_file(i : WithRawConfigFile)
    b = i.raw_config_file
    V1.parse_config_file(IO::Memory.new(b))
  end

  # config_name is a helper for implementing v1 image
  def config_name(i : WithRawConfigFile)
    b = i.raw_config_file
    if b.nil?
      raise ""
    else
      h, _ = V1::Hash.sha256(IO::Memory.new(b))
      h
    end
  rescue exception
    V1::Hash.new("", "")
  end

  private struct ConfigLayer
    include V1::Layer
    @hash : V1::Hash
    @content : Bytes

    def initialize(@hash, @content)
    end

    # digest implements v1 layer
    def digest
      @hash
    end

    def diff_id
      @hash
    end

    def uncompressed
      IO::Memory.new(@content)
    end

    def compressed
      IO::Memory.new(@content)
    end

    def size
      @content.size.to_i64
    end

    def media_type
      # Defaulting this to OCIConfigJSON as it should remain
      # backwards compatible with DockerConfigJSON
      Types::OCICONFIGJSON
    end
  end

  # ConfigLayer implements v1.Layer from the raw config bytes.
  # This is so that clients (e.g. remote) can access the config as a blob.
  def config_layer(i) # : WithRawConfigFile) : V1::Layer
    if !(i.responds_to?(:raw_config_file))
      pp i
      raise "Image doesn't comply with Partial::WithRawConfigFile protocol"
    end

    h = config_name(i.as(WithRawConfigFile))
    rcfg = i.raw_config_file
    if rcfg.nil?
      raise "Unable to get raw config file"
    else
      ConfigLayer.new(hash: h, content: rcfg)
    end
  end

  #  WithConfigFile defines the subset of v1.Image used by these helper methods
  module WithConfigFile
    # returns image config file
    abstract def config_file : V1::ConfigFile
  end

  # helper for implementing v1 image
  def diff_ids(i : WithConfigFile)
    cfg = i.config_file
    if (cfg.nil?)
      raise "config file not found. returned nil"
    else
      cfg.rootfs.diff_ids
    end
  end

  # helper for implementing v1 image
  def raw_config_file(i : WithConfigFile) : Bytes
    cfg = i.config_file
    cfg.to_json.to_slice.dup
  end

  # WithUncompressedLayer defines the subset of v1.Image used by these helper methods
  module WithUncompressedLayer
    # is like UncompressedBlob, but takes the "diff id".
    abstract def uncompressed_layer(h : V1::Hash) : IO
  end

  # Layer is the same as Blob, but takes the "diff id".
  def layer(wul : WithUncompressedLayer, h : V1::Hash)
    rc = wul.uncompressed_layer(h)
    V1::Util.gzip_reader_closer(rc)
  end

  # WithRawManifest defines the subset of v1.Image used by these helper methods
  module WithRawManifest
    # returns the serialized bytes of this image's config file.
    abstract def raw_manifest : Bytes
  end

  # digest is helper for implementing v1 image
  def digest(i : WithRawManifest)
    mb = i.raw_manifest
    if mb.nil?
      raise ""
    else
      digest, _ = V1::Hash.sha256(IO::Memory.new(mb))
      digest
    end
  rescue exception
    V1::Hash.new("", "")
  end

  # manifest is a helper for implementing v1 image
  def manifest(i : WithRawManifest)
    b = i.raw_manifest
    if (b)
      io = IO::Memory.new(b)
    else
      io = IO::Memory.new
    end

    V1.parse_manifest(io)
  end

  # WithManifest defines the subset of v1.Image used by these helper methods
  module WithManifest
    # returns this image's manifest object
    abstract def manifest : V1::Manifest
  end

  # raw_manifest is a helper for implementing v1 image
  def raw_manifest(i : WithManifest)
    i.manifest.try &.to_json.to_slice.dup
  end

  # fs_layers is a helper for implementing v1 image
  def fs_layers(mf : WithManifest)
    m = mf.manifest
    if m.nil?
      raise "Unable to get manifest"
    else
      fsl = Array(V1::Hash).new(m.layers.size)
      m.layers.each { |l| fsl << l.digest }
      fsl
    end
  end

  # blob_size is a helper for implementing v1.Image
  def blob_size(i : WithManifest, h : V1::Hash)
    m = i.manifest
    m.layers.each_with_index do |l, _|
      if l.digest == h
        return l.size
      end
    end
    raise "blob #{h} not found"
  end

  # WithManifestAndConfigFile defines the subset of v1.Image used by these helper methods
  module WithManifestAndConfigFile
    include WithConfigFile

    # returns this image's manifest object
    abstract def manifest : V1::Manifest
  end

  # blob_to_diff_id is a helper for mapping between compressed
  # and uncompressed blob hashes.
  def blob_to_diff_id(i : WithManifestAndConfigFile, h : V1::Hash)
    blobs = fs_layers(i)
    diff_ids = diff_ids(i)
    raise "mismatched fs layers (#{blobs.size}) and diff ids (#{diff_ids.size})" unless blobs.size == diff_ids.size

    blobs.each_with_index do |blob, idx|
      return diff_ids[idx] if blob == h
    end

    raise "unknown blob #{h}"
  end

  # diff_to_blob is a helper for mapping between uncompressed and compressed blob hashes
  def diff_to_blob(i : WithManifestAndConfigFile, h : V1::Hash)
    blobs = fs_layers(i)
    diff_ids = diff_ids(i)
    raise "mismatched fs layers (#{blobs.size}) and diff ids (#{diff_ids.size})" unless blobs.size == diff_ids.size

    diff_ids.each_with_index do |diff, idx|
      return blobs[idx] if diff == h
    end

    raise "unknown diffID #{h}"
  end

  # WithBlob defines the subset of v1.Image used by these helper methods
  module WithBlob
    # returns an IO for streaming the blob's content
    abstract def blob(h : V1::Hash) : IO
  end

  # uncompressed_blob returns an IO for streaming the blob's contents
  # uncompressed
  def uncompressed_blob(b : WithBlob, h : V1::Hash)
    rc = b.blob(h)
    V1::Util.gunzip_read_closer(rc)
  end

  # defines the subset of v1.Layer for exposing the DiffID method.
  module WithDiffID
    abstract def diff_id : V1::Hash
  end
end
