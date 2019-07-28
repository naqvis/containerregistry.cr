require "json"
require "crystar"
require "../partial"
require "../util/and_closer"

module V1::Tarball
  extend self

  private class Image
    getter opener : Opener
    getter td : TarDescriptor
    getter config : Bytes
    getter image_descriptor : SingleImageTarDescriptor
    getter tag : Name::Tag?

    def initialize(@opener, @tag)
      @config = Bytes.empty
      @td = TarDescriptor.new(0)
      @image_descriptor = SingleImageTarDescriptor.new
    end

    def media_type
      Types::DOCKERMANIFESTSCHEMA2
    end

    def are_layers_compressed
      return false if (image_descriptor && image_descriptor.layers.size == 0)

      layer = image_descriptor.layers[0]
      blob = Tarball.extract_file_from_tar(opener, layer)
      begin
        V1::Util.is_gzipped(blob.reader)
      ensure
        blob.close
      end
    end

    def load_tar_descriptor_and_config : Nil
      json = Tarball.extract_file_from_tar(@opener, "manifest.json")
      begin
        @td = TarDescriptor.new(json.reader)
        @image_descriptor = td.find_specified_image_descriptor(tag)
        cfg = Tarball.extract_file_from_tar(opener, image_descriptor.config)
        @config = Util.read_all(cfg.reader)
        cfg.close
      ensure
        json.close
      end
    end

    def raw_config_file
      @config
    end
  end

  private class CompressedLayerFromTarball
    include V1::Partial::CompressedLayer
    getter digest : V1::Hash
    getter opener : Opener
    getter file_path : String

    def initialize(@digest, @opener, @file_path)
    end

    def compressed
      Tarball.extract_file_from_tar(opener, file_path)
    end

    def media_type
      Types::DOCKERLAYER
    end

    def size
      r = compressed
      _, i = V1::Hash.sha256(r.reader)
      r.close
      i
    end
  end

  private class UncompressedLayerFromTarball
    include V1::Partial::UncompressedLayer
    getter diff_id : V1::Hash
    getter opener : Opener
    getter file_path : String

    def initialize(@diff_id, @opener, @file_path)
    end

    def uncompressed
      Tarball.extract_file_from_tar(opener, file_path)
    end

    def media_type
      # Technically the media type should be 'application/tar' but given that our
      # v1.Layer doesn't force consumers to care about whether the layer is compressed
      # we should be fine returning the DockerLayer media type
      Types::DOCKERLAYER
    end
  end

  private class UncompressedImage # < Image
    include V1::Partial::UncompressedImageCore
    include V1::Partial::WithRawConfigFile

    delegate raw_config_file, media_type, to: @image
    forward_missing_to @image

    def initialize(@image : Image)
    end

    def layer_by_diff_id(h : V1::Hash)
      cfg = Partial.config_file(self)
      cfg.rootfs.diff_ids.each_with_index do |diff_id, idx|
        if diff_id == h
          return UncompressedLayerFromTarball.new(
            diff_id: diff_id,
            opener: opener,
            file_path: image_descriptor.layers[idx]
          )
        end
      end

      raise "diff id #{h} not found"
    end
  end

  private class CompressedImage # < Image
    include V1::Partial::CompressedImageCore
    include V1::Partial::WithManifest

    @manifest_lock : Mutex
    @manifest : V1::Manifest?

    delegate raw_config_file, media_type, to: @image
    forward_missing_to @image

    def initialize(@image : Image)
      @manifest_lock = Mutex.new
    end

    def layer_by_digest(h : V1::Hash)
      m = manifest
      if (m)
        m.layers.each_with_index do |l, i|
          if l.digest == h
            fp = image_descriptor.layers[i]
            return CompressedLayerFromTarball.new(
              digest: h,
              opener: opener,
              file_path: fp
            )
          end
        end
      end
      raise "blob #{h} not found"
    end

    def manifest
      @manifest_lock.synchronize {
        return @manifest unless @manifest.nil?
        b = raw_config_file
        cfg_hash, cfg_size = V1::Hash.sha256(IO::Memory.new(b))
        @manifest = V1::Manifest.new(
          schema_version: 2,
          media_type: Types::DOCKERMANIFESTSCHEMA2,
          config: V1::Descriptor.new(
            media_type: Types::DOCKERCONFIGJSON,
            size: cfg_size.to_i64,
            digest: cfg_hash
          )
        )

        image_descriptor.layers.each_with_index do |p, _|
          l = Tarball.extract_file_from_tar(opener, p)
          begin
            sha, size = V1::Hash.sha256(l.reader)
            if (m = @manifest)
              m.layers << V1::Descriptor.new(
                media_type: Types::DOCKERLAYER,
                size: size.to_i64,
                digest: sha
              )
            end
          ensure
            l.close
          end
        end
      }
      @manifest
    end

    def raw_manifest
      Partial.raw_manifest(self)
    end
  end

  # SingleImageTarDescriptor is the struct used to represent a single
  # image inside a `docker save` tarball.
  struct SingleImageTarDescriptor
    JSON.mapping(
      config: {type: String, key: "Config"},
      repo_tags: {type: Array(String), key: "RepoTags"},
      layers: {type: Array(String), key: "Layers"}
    )

    def initialize(@config = "", @repo_tags = [] of String, @layers = [] of String)
    end
  end

  # TarDescriptor is the struct used inside the `manifest.json` file of a
  # `docker save` tarball.
  private struct TarDescriptor
    @td : Array(SingleImageTarDescriptor)

    def initialize(size : Int)
      @td = Array(SingleImageTarDescriptor).new(size)
    end

    def initialize(json)
      @td = Array(SingleImageTarDescriptor).from_json(json)
    end

    def <<(v : SingleImageTarDescriptor)
      @td << v
    end

    def find_specified_image_descriptor(tag : Name::Tag?)
      if tag.nil?
        raise Exception.new("tarball must contain only a single image to be used with Tarball.image") if @td.size != 1
        return @td[0]
      end

      @td.each_with_index do |img, _|
        img.repo_tags.each_with_index do |tag_str, _|
          repo_tag = Name::Tag.new(tag_str)

          # compare the resolved names, since there are several ways to specific the same tag.
          return img if repo_tag.name == tag.name
        end
      end

      raise Exception.new "tag #{tag.to_s} not found in tarball."
    end

    def to_json(json : JSON::Builder)
      @td.to_json json
    end
  end
end
