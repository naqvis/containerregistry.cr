require "gzip"

module V1::Tarball
  extend self

  class Layer
    include V1::Layer
    getter digest : V1::Hash
    getter diff_id : V1::Hash
    getter size : Int64
    getter opener : Opener
    @compressed : Bool

    def initialize(@digest, @diff_id, @size, @opener, @compressed)
    end

    # from_file returns a V1::Layer given a tarball
    def self.from_file(path : String)
      opener = Opener.new {
        File.open(path)
      }
      from_opener opener
    end

    # from_opener returns a V1::Layer given an opener function
    def self.from_opener(opener : Opener)
      rc = opener.call
      begin
        compressed = V1::Util.is_gzipped rc
        digest, size = compute_digest opener, compressed
        diff_id = compute_diff_id opener, compressed

        Layer.new(
          digest: digest,
          diff_id: diff_id,
          size: size,
          compressed: compressed,
          opener: opener
        )
      ensure
        rc.close
      end
    end

    # from_reader returns a V1::Layer given an IO
    def self.from_reader(io : IO)
      # Buffering due to Opener requiring multiple calls.
      a = V1::Util.read_all(io)
      opener = Opener.new {
        V1::Util::ReaderAndCloser.new(
          reader: IO::Memory.new(a),
          closer: ->{}
        )
      }
      from_opener opener
    end

    def self.compute_digest(opener : Opener, compressed : Bool)
      rc = opener.call
      begin
        return V1::Hash.sha256 rc if compressed
        reader = V1::Util.gzip_reader_closer V1::Util::NoOpCloser.new rc
        V1::Hash.sha256 reader
      ensure
        rc.close
      end
    end

    def self.compute_diff_id(opener : Opener, compressed : Bool)
      rc = opener.call
      begin
        if !compressed
          digest, _ = V1::Hash.sha256 rc
          return digest
        end
        reader = Gzip::Reader.new(rc)
        diff_id, _ = V1::Hash.sha256 reader
        diff_id
      ensure
        rc.close
      end
    end

    def compressed
      rc = opener.call
      return V1::Util.gzip_reader_closer(rc) if !@compressed

      rc
    end

    def uncompressed
      rc = opener.call
      return V1::Util.gunzip_reader_closer(rc) if @compressed
      rc
    end

    def media_type
      Types::DOCKERLAYER
    end
  end
end
