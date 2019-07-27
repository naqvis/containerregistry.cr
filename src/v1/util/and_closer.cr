module V1::Util
  # implements IO read and close by reading from a particular
  # IO reader and then calling the provided close method
  class ReaderAndCloser < IO
    alias Closer = ->

    getter reader : IO
    @closer : Closer

    def initialize(@reader, @closer)
    end

    def read(b : Bytes)
      reader.read(b)
    end

    def write(b : Bytes)
      raise Error.new "ReaderAndCloser: Can't write"
    end

    def close
      @closer.call
    end

    forward_missing_to @reader
  end

  class NoOpCloser < ReaderAndCloser
    @r : IO

    def initialize(@r)
      super(@r, ->{ close })
    end

    def close
      # do nothing
    end

    def write(b : Bytes)
      raise Error.new "NoOpReader: Can't write"
    end

    forward_missing_to @r
  end
end
