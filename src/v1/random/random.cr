# Module Random provides a facility for synthesizing pseudo-random images.
module V1::Random
  extend self

  # image returns a pseudo-randomly generated Image.
  def image(size : Int64, layers : Int64)
    layerz = ::Hash(V1::Hash, V1::Partial::UncompressedLayer).new
    0.upto(layers - 1) do |i|
      buf = IO::Memory.new
      Crystar::Writer.open(buf) do |tw|
        hdr = Crystar::Header.new(
          name: "random_file_#{i}.txt",
          size: size,
          flag: Crystar::REGA.ord.to_u8
        )
        tw.write_header hdr
        tw.write ::Random::Secure.random_bytes size
      end
      buf.rewind
      h, _ = V1::Hash.sha256 buf
      layerz[h] = UncompressedLayer.new diff_id: h, content: buf.to_slice
    end

    cfg = V1::ConfigFile.new(
      architecture: "amd64",
      os: "linux",
      rootfs: V1::RootFS.new(type: "layers",
        diff_ids: Array(String).new.tap { |arr|
          layerz.each_key do |k|
            arr << k.to_s
          end
        }),
      history: Array(V1::History).new.tap { |arr|
        0.upto(layers - 1) do |i|
          arr << V1::History.new(
            author: "V1::Random.image",
            comment: "this is a random history #{i}",
            created_by: "random",
            created: Time.utc
          )
        end
      },
      config: V1::Config.new
    )

    V1::Partial.uncompressed_to_image(Image.new(config: cfg, layers: layerz))
  end

  # Index returns a pseudo-randomly generated ImageIndex with count images, each
  # having the given number of layers of size byteSize.
  def index(size : Int, layers : Int, count : Int)
    manifest = V1::IndexManifest.new(
      schema_version: 2,
      manifests: Array(V1::Descriptor).new
    )

    images = ::Hash(V1::Hash, V1::Image).new
    0.upto(count - 1) do |_|
      img = image(size.to_i64, layers.to_i64)
      raw_manifest = img.raw_manifest
      if (rm = raw_manifest)
        digest, digest_size = V1::Hash.sha256(IO::Memory.new rm)
        media_type = img.media_type
        manifest.manifests << V1::Descriptor.new(
          digest: digest,
          size: digest_size,
          media_type: media_type
        )
        images[digest] = img
      else
        raise "Unable to get Raw manifest"
      end
    end
    RandomIndex.new(images: images, manifest: manifest)
  end
end

require "./*"
