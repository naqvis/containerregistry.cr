require "atomic"

module V1::Util
  struct Once
    def initialize
      @done = Atomic(Int32).new(0)
      @m = Mutex.new
    end

    def do(f : -> (Void))
      return if @done.get == 1

      @m.synchronize {
        if @done.get == 0
          begin
            f.call
          ensure
            @done.add(1)
          end
        end
      }
    end
  end

  def self.read_all(r : IO)
    io = IO::Memory.new
    buf = Bytes.new(512)
    loop do
      begin
        n = r.read(buf)
      rescue IO::EOFError
        n = 0
      end
      break if n == 0
      io.write(buf[...n])
      clear(buf)
    end
    io.to_slice
  end

  private def clear(b : Bytes)
    p = b.to_unsafe
    p.clear(b.size)
  end
end
