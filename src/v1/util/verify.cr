require "openssl"

module V1::Util
  class TeeReader < IO
    @r : IO
    @w : IO

    def initialize(@r, @w)
    end

    def read(slice : Bytes)
      n = @r.read(slice)
      @w.write(slice[0, n]) unless n == 0
      n
    end

    def write(slice : Bytes)
      raise IO::Error.new("Can't write to V1::Util::TeeReader")
    end
  end

  private class VerifyReader < IO
    @inner : IO
    @hasher : OpenSSL::DigestIO
    @expected : V1::Hash

    def initialize(@inner, @hasher, @expected)
    end

    def read(slice : Bytes)
      n = @inner.read(slice)
      if n == 0
        got = @hasher.digest.hexstring
        if @expected.hex != got
          raise "error verifying #{@expected.algorithm} checksum; got #{got}, want #{@expected.hex}"
        end
      end
      n
    end

    def write(slice : Bytes)
      raise IO::Error.new("Can't write to V1::Util::VerifyReader")
    end
  end

  # verify_read_closer wraps the given IO to verify that its contents match
  # the provided V1::Hash before EOF is returned
  def self.verify_read_closer(r : IO, h : V1::Hash)
    w = V1::Hash.hasher(h.algorithm)
    r2 = TeeReader.new(r, w)
    ReaderAndCloser.new(
      reader: VerifyReader.new(r2, w, h),
      closer: ->{ r.close }
    )
  end
end
