require "file_utils"

module V1::Cache
  # Cacher implementation backed by files.
  class FileSystemCache < Cacher
    @path : String

    def initialize(@path)
    end

    def put(l : V1::Layer)
      digest = l.digest
      diff_id = l.diff_id
      Layer.new(
        layer: l,
        path: @path,
        digest: digest,
        diff_id: diff_id
      )
    end

    def get(h : V1::Hash)
      Tarball::Layer.from_file(Path[@path, h.to_s].to_s)
    rescue Errno
      raise LayerNotFound.new "layer was not found"
    end

    def delete(h : V1::Hash)
      FileUtils.rm_r Path[@path, h.to_s].to_s
    rescue Errno
      raise LayerNotFound.new "layer was not found"
    end
  end

  private class Layer
    include V1::Layer
    @layer : V1::Layer
    @path : String
    @digest : V1::Hash
    @diff_id : V1::Hash

    delegate digest, diff_id, size, media_type, to: @layer

    def initialize(@layer, @path, @digest, @diff_id)
    end

    def create(h : V1::Hash)
      FileUtils.mkdir_p(@path, mode: 0o700)
      File.open(Path[@path, h.to_s], "w")
    end

    def compressed
      f = create @digest
      rc = @layer.compressed

      ReadCloser.new(
        t: V1::Util::TeeReader.new(rc, f),
        closes: [proc(rc), proc(f)]
      )
    end

    def uncompressed
      f = create @diff_id
      rc = @layer.uncompressed

      ReadCloser.new(
        t: V1::Util::TeeReader.new(rc, f),
        closes: [proc(rc), proc(f)]
      )
    end

    private def proc(i : IO)
      ->{ i.close }
    end
  end

  private class ReadCloser < IO
    alias Closer = ->
    @t : IO
    @closes : Array(Closer)
    forward_missing_to @t

    def initialize(@t, @closes)
    end

    def read(b : Bytes)
      @t.read(b)
    end

    def write(b : Bytes)
      raise Error.new "ReadCloser: Can't write"
    end

    def close
      # Call all close methods, even if any returned an error. Return the
      # first returned error
      err : Exception? = nil

      @closes.each do |c|
        c.call
      rescue ex
        err = ex if err.nil?
      end

      raise err if !err.nil?
    end
  end
end
