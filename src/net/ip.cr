require "./*"

module Net
  extend self
  # IP address lenghts in bytes
  IPV4LEN =  4
  IPV6LEN = 16

  # An IP is a single IP address, a slice of bytes.
  # Functions in this package accept either 4-byte (IPv4)
  # or 16-byte (IPv6) slices as input.
  #
  # Note that in this documentation, referring to an
  # IP address as an IPv4 address or an IPv6 address
  # is a semantic property of the address, not just the
  # length of the byte slice: a 16-byte slice can still
  # be an IPv4 address.
  class IP < IPBase
    MAX_IPV4_STRING_LEN = "255.255.255.255".size

    # parse parses s as an IP address, returning the result.
    # The string s can be in dotted decimal ("192.0.2.1")
    # or IPv6 ("2001:db8::68") form.
    # If s is not a valid textual representation of an IP address,
    # parse returns nil.

    def self.parse(s : String)
      return nil if s.blank?
      s.chars.each do |c|
        case c
        when '.'
          return parse_ipv4 s
        when ':'
          return parse_ipv6 s
        end
      end
      nil
    end

    # reports whether ip is an unspecified address, either
    # the IPV4 address 0.0.0.0 or the IPV6 address ::
    def unspecified?
      self == IPV4_ZERO || self == IPV6_UNSPECIFIED
    end

    # reports whether ip is a loopback address.
    def loopback?
      if (ip4 = to4)
        return ip4[0] == 127
      end
      self == IPV6_LOOPBACK
    end

    # reports whether ip is a multicast address.
    def multicast?
      if (ip4 = to4)
        return ip4[0] & 0xf0 == 0xe0
      end
      size == IPV6LEN && self[0] == 0xff
    end

    # reports whether ip is an interface-local multicast address.
    def interface_local_multicast?
      size == IPV6LEN && self[0] == 0xff && (self[1] & 0xff == 0x01)
    end

    # converts the IPv4 address ip to a 4-byte representation.
    # If ip is not an IPV4 address, returns nil
    def to4
      return self if size == IPV4LEN
      if size == IPV6LEN && self[0, 10].all? { |b| b == 0 } &&
         self[10] == 0xff &&
         self[11] == 0xff
        self._buffer = self[12...16]
        return self
      end
      nil
    end

    # converts the IP address ip to a 16-byte representation.
    # if ip is not an IP address (it is the wrong length), returns nil
    def to16
      return Net.ipv4(self[0], self[1], self[2], self[3]) if size == IPV4LEN
      return self if size == IPV6LEN
      nil
    end

    # default_mask returns the default IP mask for the IP address ip.
    # Only IPv4 addresses have default masks; default_mask returns
    # nil if ip is not a valid IPv4 address.
    def default_mask
      return nil if (ip = to4) && ip.nil?
      case
      when self[0] < 0x80
        CLASS_A_MASK
      when self[0] < 0xC0
        CLASS_B_MASK
      else
        CLASS_C_MASK
      end
    end

    def ==(other : self)
      if size != other.size
        if size == IPV4LEN && other.size == IPV6LEN
          return self._buffer == other[12..]
        elsif other.size == IPV4LEN && size == IPV6LEN
          return other._buffer == self[12..]
        else
          return false
        end
      end
      self._buffer == other._buffer
    end

    # mask returns the result of masking the IP address ip with mask.
    def mask(m : IPMask)
      if m.size == IPV6LEN && size == IPV4LEN && Net.all_ff?(m[0, 12])
        m = m[12..]
      end
      if m.size == IPV4LEN && size == IPV6LEN && self[0, 12].to_a == V4_IN_V6PREFIX
        self._buffer = self[12..]
      end
      n = size
      return nil if n != m.size

      res = IP.new(n)
      0.upto(n - 1) do |i|
        res[i] = self[i] & m[i]
      end
      res
    end

    protected def self.parse_ipv4(s : String)
      return nil if s.blank? # missing octets
      ip = Bytes.new(IPV4LEN)
      0.upto(ip.size - 1) do |i|
        if i > 0
          return nil if s[0] != '.'
          s = s[1..]
        end
        n, c, ok = Net.dtoi(s)
        return nil if !ok || n > 0xFF
        s = s[c..]
        ip[i] = n.to_u8
      end
      return nil if s.size != 0

      Net.ipv4(ip[0], ip[1], ip[2], ip[3])
    end

    protected def self.parse_ipv6(s : String)
      ip = IP.new(IPV6LEN)
      ellipsis = -1 # position of ellipsis in ip

      # might have leading elipsis
      if s.size >= 2 && s[0] == ':' && s[1] == ':'
        ellipsis = 0
        s = s[2..]
        # might be only ellipsis
        return ip if s.size == 0
      end

      # Loop, parsing hex numbers followed by colon.
      i = 0
      while i < IPV6LEN
        # Hex number
        n, c, ok = Net.xtoi(s)
        return nil if !ok || n > 0xFFFF

        # if followed by dot, might be in trailing IPv4.
        if c < s.size && s[c] == '.'
          return nil if ellipsis < 0 && i != IPV6LEN - IPV4LEN # not the right place
          return nil if i + IPV4LEN > IPV6LEN                  # not enough room
          ipv4 = parse_ipv4(s)
          if ipv4.nil?
            return nil
          else
            ip[i] = ipv4[12]
            ip[i + 1] = ipv4[13]
            ip[i + 2] = ipv4[14]
            ip[i + 3] = ipv4[15]
            s = ""
            i += IPV4LEN
            break
          end
        end

        # Save this 16-bit chunk
        ip[i] = (n >> 8).to_u8
        ip[i + 1] = n.to_u8
        i += 2

        # Stop at end of string
        s = s[c..]
        break if s.size == 0

        # Otherwise must be followed by colon and more.
        return nil if s[0] != ':' || s.size == 1
        s = s[1..]

        # Look for ellipsis
        if s[0] == ':'
          return nil if ellipsis >= 0 # already have one
          ellipsis = i
          s = s[1..]
          break if s.size == 0 # can be at end
        end
      end

      # must have used entire string.
      return nil if s.size != 0

      # If didn't parse enough, expand ellipsis
      if i < IPV6LEN
        return nil if ellipsis < 0
        n = IPV6LEN - i
        (i - 1).downto(ellipsis) do |j|
          ip[j + n] = ip[j]
        end
        (ellipsis + n - 1).downto(ellipsis) do |j|
          ip[j] = 0_u8
        end
      elsif ellipsis >= 0
        return nil # ellipsis must represent at least one 0 group
      end
      ip
    end

    # to_s returns the string form of the IP address ip.
    # It returns one of 4 forms:
    #   - "<nil>", if ip has length 0
    #   - dotted decimal ("192.0.2.1"), if ip is an IPv4 or IP4-mapped IPv6 address
    #   - IPv6 ("2001:db8::1"), if ip is a valid IPv6 address
    #   - the hexadecimal form of ip, without punctuation, if no other cases apply

    def to_s
      p = _buffer
      return "<nil>" if size == 0

      # If IPv4 use dotted notation.
      if (p4 = to4) && p4.size == IPV4LEN
        b = Bytes.new(MAX_IPV4_STRING_LEN)
        n = Net.ubtoa(b, 0, p4[0])
        b[n] = '.'.ord.to_u8
        n += 1

        n += Net.ubtoa(b, n, p4[1])
        b[n] = '.'.ord.to_u8
        n += 1

        n += Net.ubtoa(b, n, p4[2])
        b[n] = '.'.ord.to_u8
        n += 1

        n += Net.ubtoa(b, n, p4[3])

        return String.new(b[0, n])
      end

      return "?" + hexstring if p.size == IPV6LEN

      # Find longest run of zeros.
      e0 = -1
      e1 = -1
      i = 0
      while i < IPV6LEN
        j = i
        while j < IPV6LEN && p[j] == 0 && p[j + 1] == 0
          j += 2
        end
        if j > i && j - i > e1 - e0
          e0 = i
          e1 = j
          i = j
        end
        i += 2
      end
      # The symbol `::` MUST NOT be used to shorten just one 16 bit 0 field.
      if e1 - e0 <= 2
        e0 = -1
        e1 = -1
      end

      str = String.build do |s|
        # Print with possible :: in place of run of zeros
        i = 0
        while i < IPV6LEN
          if i == e0
            s << "::"
            i = e1
            break if i >= IPV6LEN
          elsif i > 0
            s << ":"
          end
          s << Net.to_hex (p[i].to_u32 << 8) | p[i + 1].to_u32
          i += 2
        end
      end
      str
    end
  end

  alias Byte = UInt8

  # IPMask is an IP address
  class IPMask < IPBase
    # mask_size returns the number of leading ones and total bits in the mask.
    # If the mask is not in the canonical form--ones followed by zeros--then
    # mask_size returns 0, 0.
    def mask_size
      ones, bits = Net.simple_mask_length(self), size*8
      return {0, 0} if ones == -1
      {ones, bits}
    end

    def self.parse(s : String)
      ip = IP.parse(s)
      if ip
        res = IPMask.new ip.size
        res._buffer = ip._buffer
        return res
      end
      nil
    end

    # returns the hexadecimal form of mask, with no punctuation.
    def to_s
      return "<nil>" if size == 0

      hexstring
    end
  end

  # An IPNet represents an IP network
  class IPNet
    getter ip : IP       # network number
    getter mask : IPMask # network mask

    def initialize(@ip, @mask)
    end

    # reports whether the network includes ip
    def contains?(ip : IP)
      nn, m = Net.network_number_and_mask(self)
      if (x = ip.to4)
        ip = x
      end
      l = ip.size
      return false if l != Net.len(nn)

      0.upto(l - 1) do |i|
        nv = Net.get_val(nn, i)
        mv = Net.get_val(m, i)
        pv = Net.get_val(ip, i)

        if nv & mv != pv & mv
          return false
        end
      end
      true
    end

    # network returns the address's network name, "ip+net"
    def network
      "ip+net"
    end

    # to_s returns the CIDR notation of n like "192.0.2.1/24"
    # or "2001:db8::/48" as defined in RFC 4632 and RFC 4291.
    # If the mask is not in the canonical form, it returns the
    # string which consists of an IP address, followed by a slash
    # character and a mask expressed as hexadecimal form with no
    # punctuation like "198.51.100.1/c000ff00".
    def to_s
      nn, m = Net.network_number_and_mask(self)
      return "<nil>" if nn.nil? || m.nil?
      l = Net.simple_mask_length(m)
      return nn.to_s + "/" + m.to_s if l == -1

      nn.to_s + "/" + Net.uitoa(l.to_u32)
    end
  end

  V4_IN_V6PREFIX = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff] of Byte

  # ipv4 returns the IP address (in 16-byte form) of the
  # ipv4 address a.b.c.d.
  def ipv4(a : Byte, b : Byte, c : Byte, d : Byte) : IP
    ip = IP.new(IPV6LEN)
    V4_IN_V6PREFIX.size.times do |i|
      ip[i] = V4_IN_V6PREFIX[i]
    end
    ip[12] = a
    ip[13] = b
    ip[14] = c
    ip[15] = d

    ip
  end

  # IPv4Mask returns the IP mask (in 4-byte form) of the
  # IPv4 mask a.b.c.d.
  def ipv4_mask(a : Byte, b : Byte, c : Byte, d : Byte) : IPMask
    mask = IPMask.new(IPV4LEN)

    mask[0] = a
    mask[1] = b
    mask[2] = c
    mask[3] = d

    mask
  end

  # cidr_mask returns an IPMask consisting of `ones' 1 bits
  # followed by 0s up to a total length of `bits' bits.
  # For a mask of this form, cidr_mask is the inverse of IPMask.Size.
  def cidr_mask(ones : Int, bits : Int) : IPMask?
    if bits != 8*IPV4LEN && bits != 8*IPV6LEN
      return nil
    end
    if ones < 0 || ones > bits
      return nil
    end
    l = bits // 8
    m = IPMask.new(l)
    n = ones
    0.upto(l - 1) do |i|
      if n >= 8
        m[i] = 0xff_u8
        n -= 8
        next
      end
      m[i] = ~(0xff >> n).to_u8
      n = 0
    end
    m
  end

  # parse_cidr parses s as a CIDR notation IP address and prefix length,
  # like "192.0.2.0/24" or "2001:db8::/32", as defined in
  # RFC 4632 and RFC 4291.
  #
  # It returns the IP address and the network implied by the IP and
  # prefix length.
  # For example, parse_cidr("192.0.2.1/24") returns the IP address
  # 192.0.2.1 and the network 192.0.2.0/24.

  def parse_cidr(s : String)
    idx = s.index('/')
    if (i = idx)
      addr, mask = s[0, i], s[i + 1..]
      iplen = IPV4LEN
      ip = IP.parse_ipv4(addr)
      if ip.nil?
        iplen = IPV6LEN
        ip = IP.parse_ipv6(addr)
      else
        n, i, ok = dtoi mask
        if ip.nil? || !ok || i != mask.size || n < 0 || n > 8*iplen
          return {nil, nil}
        else
          m = cidr_mask n, 8*iplen
          if m.nil?
            return {ip, nil}
          else
            nip = ip.mask(m)
            if nip.nil?
              return {ip, nil}
            else
              return {ip, IPNet.new(ip: nip, mask: m)}
            end
          end
        end
      end
    end
    raise "invalid CIDR address. #{s}"
  end

  # Default route masks for IPv4
  CLASS_A_MASK = Net.ipv4_mask(0xff, 0, 0, 0)
  CLASS_B_MASK = Net.ipv4_mask(0xff, 0xff, 0, 0)
  CLASS_C_MASK = Net.ipv4_mask(0xff, 0xff, 0xff, 0)

  # Well-known IPv4 addresses
  IPV4_BCAST     = ipv4(255, 255, 255, 255) # limited broadcast
  IPV4_ALLSYS    = ipv4(224, 0, 0, 1)       # all systems
  IPV4_ALLROUTER = ipv4(224, 0, 0, 2)       # ALL ROUTERS
  IPV4_ZERO      = ipv4(0, 0, 0, 0)         # all zeros

  # Well-known IPv6 addresses
  IPV6_ZERO                      = IP[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  IPV6_UNSPECIFIED               = IP[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  IPV6_LOOPBACK                  = IP[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
  IPV6_INTERFACE_LOCAL_ALL_NODES = IP[0xff, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01]
  IPV6_LINK_LOCAL_ALL_NODES      = IP[0xff, 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01]
  IPV6_LINK_LOCAL_ALL_ROUTERS    = IP[0xff, 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x02]
end
