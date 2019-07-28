module V1
  # Hash is an unqualified digest of some content, e.g. sha256:deadbeef
  struct Hash
    # Algorithm holds the algorithm used to compute the hash.
    getter algorithm : String = ""
    # Hex holds the hex portion of the content hash.
    getter hex : String = ""

    def initialize(@algorithm, @hex)
    end

    def initialize(h : String)
      parse(h)
    end

    def to_s
      "#{@algorithm}:#{hex}"
    end

    def self.empty
      new("sha256", "b1d4e2e6ccaf0081ea23a20da8b8fbb49682937bf853a7fdab851beb6e1bab81")
    end

    def self.new(pull : JSON::PullParser)
      pull.read_string
    end

    def self.from_json(pull : JSON::PullParser)
      string = pull.read_string
      new(string)
    end

    def self.to_json(json : JSON::Builder)
      json.string(self.to_s)
    end

    def self.to_json(h : Hash, json : JSON::Builder)
      json.string(h.to_s)
    end

    def self.sha256(r : IO)
      io = OpenSSL::DigestIO.new(r, "SHA256")
      buffer = Bytes.new(32 * 1024)
      size = 0_i64
      while (n = io.read(buffer)) && n > 0
        size += n
        clear(buffer)
      end

      {Hash.new("sha256", io.digest.hexstring), size}
    end

    def self.hasher(name : String)
      case name
      when "sha256"
        OpenSSL::DigestIO.new(IO::Memory.new, "SHA256", OpenSSL::DigestIO::DigestMode::Write)
      else
        raise Exception.new("unsupported hash: #{name}")
      end
    end

    private def self.clear(b : Bytes)
      p = b.to_unsafe
      p.clear(b.size)
    end

    private def parse(h : String)
      parts = h.split(':')
      if parts.size != 2
        raise Exception.new("too many parts in hash: #{h}")
      end
      rest = parts[1].lstrip("0123456789abcdef")
      raise Exception.new("found non-hex character in hash: #{rest}") if rest.size != 0

      case parts[0]
      when "sha256" then sha = OpenSSL::Digest.new("SHA256")
      else
        raise Exception.new("unsupported hash: #{parts[0]}")
      end

      if parts[1].size != sha.digest_size * 2
        raise Exception.new("wrong number of hex digits for #{parts[0]}: #{parts[1]}")
      end

      @algorithm = parts[0]
      @hex = parts[1]
    end
  end
end

require "json"
require "openssl"
