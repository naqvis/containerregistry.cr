module Net
  extend self

  protected def get_val(b, i)
    return 0_u8 if b.nil?
    if (a = b)
      return a[i]
    end
    0_u8
  end

  protected def len(v)
    return 0 if v.nil?
    if (t = v) && t.responds_to?(:size)
      return t.size
    end
    0
  end

  protected def network_number_and_mask(n : IPNet)
    ip = n.ip.to4
    m = n.mask
    if ip.nil?
      ip = n.ip
      return {nil, nil} if ip.size != IPV6LEN
    end

    case m.size
    when IPV4LEN
      return {nil, nil} if ip.size != IPV4LEN
    when IPV6LEN
      m = m[12..] if ip.size == IPV4LEN
    else
      return {nil, nil}
    end
    {ip, m}
  end

  # If mask is a sequence of 1 bits followed by 0 bits,
  # returns the number of 1 bits.
  def simple_mask_length(mask : IPMask)
    n = 0
    mask.each_with_index do |v, i|
      if v == 0xff
        n += 8
        next
      end

      # found non-ff byte
      # count 1 bits
      while v & 0x80 != 0
        n += 1
        v <<= 1
      end

      # rest must be 0 bits
      return -1 if v != 0

      i += 1
      while i < mask.size
        return -1 if mask[i] != 0
        i += 1
      end
      break
    end
    n
  end

  def zeros?(p : IP)
    p.all? { |a| a == 0 }
  end

  def all_ff?(b : Bytes)
    b.all? { |a| a == 0xff }
  end

  # convert i to a hexadecimal string. Leading zeros are not printed.
  def to_hex(i : UInt32)
    hex_digit = "0123456789abcdef"
    return "0" if i == 0
    str = String.build do |dst|
      7.downto(0) do |j|
        v = i >> (j*4).to_u32
        dst << hex_digit[v & 0xf] if v > 0
      end
    end
    str
  end

  # ubtoa encodes the string form of the integer v to dst and
  # returns the number of bytes written to dst. The caller must
  # ensure that dst has sufficient length
  def ubtoa(dst : Bytes, start : Int, v : UInt8)
    if v < 10
      dst[start] = v + '0'.ord
      return 1
    elsif v < 100
      dst[start + 1] = v % 10 + '0'.ord
      dst[start] = v // 10 + '0'.ord
      return 2
    end

    dst[start + 2] = v % 10 + '0'.ord
    dst[start + 1] = (v//10) % 10 + '0'.ord
    dst[start] = v//100 + '0'.ord
    3
  end

  # Convert unsigned integer to decimal string.
  def uitoa(val : UInt)
    return "0" if val == 0 # avoid string allocation
    buf = Bytes.new(20)    # big enough for 64bit value base 10
    i = buf.size - 1

    while val >= 10
      q = val // 10
      buf[i] = ('0'.ord + val - q*10).to_u8
      i -= 1
      val = q
    end
    # val < 10
    buf[i] = ('0'.ord + val).to_u8
    String.new(buf[i..])
  end

  # Bigger than we need, not too big to worry about overflow
  BIG = 0xFFFFFF

  # decimal to integer, returns number, characters consumed, success
  def dtoi(s : String)
    n = i = 0
    while i < s.size && '0' <= s[i] && s[i] <= '9'
      n = n * 10 + (s[i] - '0')
      return {BIG, i, false} if n >= BIG
      i += 1
    end
    return {0, 0, false} if i == 0
    {n, i, true}
  end

  # Hexadecimal to integer. Returns number, characters consumed, success
  def xtoi(s : String)
    n = i = 0
    while i < s.size
      if '0' <= s[i] && s[i] <= '9'
        n *= 16
        n += (s[i] - '0').to_i
      elsif 'a' <= s[i] && s[i] <= 'f'
        n *= 16
        n += (s[i] - 'a').to_i + 10
      elsif 'A' <= s[i] && s[i] <= 'F'
        n *= 16
        n += (s[i] - 'A').to_i + 10
      else
        break
      end
      return {0, i, false} if n >= BIG
      i += 1
    end
    return {0, i, false} if i == 0
    {n, i, true}
  end
end
