module Net
  abstract class IPBase
    @buffer : Bytes

    macro [](*nums)
      %ptr = Pointer(UInt8).malloc({{nums.size}})
        {% for arg, i in nums %}
        %ptr[{{i}}] = UInt8.new({{arg}})
        {% end %}
      IP.new(%ptr, {{nums.size}} )
    end

    def self.empty
      new(Pointer(UInt8).null, 0)
    end

    def initialize(ptr : Pointer(UInt8), size : Int)
      @buffer = Bytes.new(ptr, size)
    end

    def self.new(size : Int)
      pointer = Pointer(UInt8).malloc(size)
      new(pointer, size)
    end

    def self.new(size : Int)
      pointer = Pointer.malloc(size) { |i| yield i.to_u8 }
      new(pointer, size)
    end

    protected def _buffer
      @buffer
    end

    protected def _buffer=(v : Bytes)
      # @buffer.copy_from(v)
      @buffer = v
    end

    def_equals_and_hash @buffer

    forward_missing_to @buffer
  end
end
