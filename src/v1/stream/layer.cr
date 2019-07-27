require "gzip"
require "openssl"
require "../partial"

module V1::Stream
  # Layer is a streaming implementation of V1::Layer.
  class Layer
    include Partial::CompressedLayer
    include V1::Layer

    getter blob : IO
    property consumed : Bool = false
    getter mu : Mutex = Mutex.new
    property digest : V1::Hash?
    property diff_id : V1::Hash?
    property size : Int64 = 0

    def initialize(@blob)
    end

    def digest
      @mu.synchronize {
        if (d = @digest)
          d
        else
          raise ExNotComputed.new("value not computed until stream is consumed")
        end
      }
    end

    def diff_id
      @mu.synchronize {
        if (d = @diff_id)
          d
        else
          raise ExNotComputed.new("value not computed until stream is consumed")
        end
      }
    end

    def size
      @mu.synchronize {
        raise ExNotComputed.new("value not computed until stream is consumed") if @size == 0
        @size
      }
    end

    def media_type
      # We return DOCKERLAYER for now as uncompressed layers are unimplemented
      Types::DOCKERLAYER
    end

    def uncompressed
      raise "Not Implemented: Stream::Layer#uncompressed not yet implemented"
    end

    def compressed
      raise ExConsumed.new "stream was already consumed" if @consumed
      CompressedReader.new(self)
    end
  end

  private class CompressedReader < IO
    @l : Layer
    @h : OpenSSL::DigestIO  # collects digest of ucompressed stream
    @zh : OpenSSL::DigestIO # collections digest of compressed stream
    @pr : IO
    @count : CountWriter

    def initialize(@l)
      @h = OpenSSL::DigestIO.new(IO::Memory.new, "SHA256", OpenSSL::DigestIO::DigestMode::Write)
      @zh = OpenSSL::DigestIO.new(IO::Memory.new, "SHA256", OpenSSL::DigestIO::DigestMode::Write)
      @count = CountWriter.new
      @closed = false
      # Gzip::Writer writes to the output stream via pipe, a hasher to
      # capture compressed digest, and a CountWriter to capture compressed size.
      @pr, pw = IO.pipe
      zw = Gzip::Writer.new(IO::MultiWriter.new(pw, @zh, @count)) # , level: Gzip::BEST_SPEED)
      @closer = MultiCloser.new(zw, @l.blob)
      spawn do
        begin
          IO.copy @l.blob, IO::MultiWriter.new(@h, zw)
        rescue ex
          pw.close
        else
          # Now close the compressed reader, to flush the gzip stream
          # and calculate digest/diffID/size. This will cause pr to
          # return EOF which will cause readers of the Compressed stream
          # to finish reading.
          close
          pw.close
        end
      end
    end

    def read(slice : Bytes)
      @pr.read(slice)
    end

    def write(slice : Bytes)
      raise "CompressedReader: Can't write"
    end

    def close
      return if @closed
      @l.mu.synchronize {
        # Close the inner Reader
        @closer.close
        @l.diff_id = V1::Hash.new("sha256:#{@h.digest.hexstring}")
        @l.digest = V1::Hash.new("sha256:#{@zh.digest.hexstring}")
        @l.size = @count.size
        @l.consumed = true
        @closed = true
      }
    end
  end

  private class CountWriter < IO
    getter size : Int64

    def initialize
      @size = 0
    end

    def read(slice : Bytes)
      raise "CountWriter: Can't read"
    end

    def write(slice : Bytes)
      @size += slice.size
    end
  end

  private class MultiCloser
    @vals : Array(IO)

    def initialize(*ios : IO)
      @vals = Array(IO).new(ios.size)
      ios.each do |i|
        @vals << i
      end
    end

    def close
      @vals.each do |v|
        v.close
      end
    end
  end
end
