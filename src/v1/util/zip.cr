require "gzip"

module V1::Util
  extend self
  GZIP_MAGIC_HEADER = Bytes[0x1f, 0x8b]

  # reads uncompressed input data from the IO and
  # returns an IO from which compressed data may be read.
  # This uses Gzip::BEST_COMPRESSION for the compression level

  def gzip_reader_closer(r : IO)
    gzip_reader_closer(r, Gzip::BEST_COMPRESSION)
  end

  # reads uncompressed input data from the IO and
  # returns an IO from which compressed data may be read.
  # Refer to  Gzip constants for the compression level

  def gzip_reader_closer(r : IO, level)
    pr, pw = IO.pipe

    spawn do
      Gzip::Writer.open(pw, level: level, sync_close: true) do |gzip|
        IO.copy(r, gzip)
      end
    ensure
      r.close
      pw.close
    end
    pr
  end

  # reads compressed input data from the IO and
  # returns an IO from which uncompressed data may be read
  def gunzip_reader_closer(r : IO)
    gr = Gzip::Reader.new r
    ReaderAndCloser.new reader: gr,
      closer: ->{
        gr.close
        r.close
      }
  end

  # detects whether the input stream is compressed
  def is_gzipped(r : IO)
    h = Bytes.new(2)
    r.read(h)
    h == GZIP_MAGIC_HEADER
  end
end
