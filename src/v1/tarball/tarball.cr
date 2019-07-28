# Module Tarball provides facilities for reading/writing v1.Images from/to a tarball on-disk.
module V1::Tarball
  extend self
  alias Opener = Proc(IO)

  def path_opener(path : String)
    Opener.new { File.open(path) }
  end

  # image_from_path returns a V1::Image from a tarball located on path.
  def image_from_path(path : String, tag : Name::Tag?)
    image(path_opener(path), tag)
  end

  # image exposes an image from the tarball at the provided path.
  def image(opener : Opener, tag : Name::Tag?)
    img = Image.new(opener: opener, tag: tag)
    img.load_tar_descriptor_and_config

    # Peek at the first layer and see if it's compressed

    compressed = img.are_layers_compressed

    if compressed
      c = CompressedImage.new(img)
      return Partial.compressed_to_image(c)
    end

    uc = UncompressedImage.new(img)
    Partial.uncompressed_to_image(uc)
  end

  protected def extract_file_from_tar(opener : Opener, filepath : String)
    f = opener.call
    Crystar::Reader.open(f) do |tf|
      tf.each_entry do |hdr|
        if hdr.name == filepath
          return Util::ReaderAndCloser.new(reader: hdr.io,
            closer: ->{ f.close })
        end
      end
    end
    raise "file #{filepath} not found in tar"
  end
end

require "./*"
