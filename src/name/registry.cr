require "uri"
require "../net/ip"

module Name
  # DefaultRegistry is Docker Hub, assumed when a hostname is omitted.
  DEFAULT_REGISTRY       = "index.docker.io"
  DEFAULT_REGISTRY_ALIAS = "docker.io"
  RFC1918_CIDR           = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  # Exceptions when a bad docker name is supplied.
  class Name::BadNameException < Exception
  end

  # Stores a docker registry name in a structured form.
  class Registry
    getter :registry, :insecure, :strict

    def initialize(name, @insecure = false, @strict = true)
      if @strict && name.blank?
        raise BadNameException.new("strict validation requires the registry to be explicitly defined")
      end

      if name.blank? || name == DEFAULT_REGISTRY_ALIAS
        @registry = DEFAULT_REGISTRY
      else
        check_registry(name)
        @registry = name
      end
    end

    def scope(action : String)
      # The only resource under 'registry' is 'catalog'. http://goo.gl/N9cN9Z
      "registry:catalog:*"
    end

    def scheme
      # Detect more complex forms of local references.
      re_local = /.*\.local(?:host)?(?::\d{1,5})?$/
      # Detect the loopback IP (127.0.0.1)
      re_loopback = /127\.0\.0\.1/
      # Detect the loopback IPV6 (::1)
      re_ipv6_loopback = /::1/

      case
      when insecure                             then "http"
      when rfc1918?                             then "http"
      when @registry.starts_with?("localhost:") then "http"
      when re_local.match(@registry)            then "http"
      when re_loopback.match(@registry)         then "http"
      when re_ipv6_loopback.match(@registry)    then "http"
      else                                           "https"
      end
    end

    def to_s
      reg_name
    end

    def reg_name
      @registry.blank? ? DEFAULT_REGISTRY : @registry
    end

    def_equals_and_hash @registry, @insecure, @strict

    def rfc1918?
      ip_str = reg_name.split(":")[0]
      ip = Net::IP.parse(ip_str)
      if ip.nil?
        return false
      else
        RFC1918_CIDR.each do |cidr|
          _, net = Net.parse_cidr(cidr)
          if net
            return true if net.contains?(ip)
          end
        end
      end
      false
    end

    private def check_registry(name)
      # Check for IPV6 loopback, Crystal parser doesn't handle them properly
      return if /::1/.match(name)
      # Per RFC 3986, registries (authorities) are required to be prefixed with "//"
      uri = URI.parse("//#{name}")
      s = ""
      if (host = uri.host)
        s = host.includes?(" ") ? "" : host
      end
      if (port = uri.port)
        s = "#{s}:#{port}"
      end
      if s != name
        raise BadNameException.new("registries must be valid RFC 3986 URI authorities: #{name}")
      end
    end

    protected def check_element(name, element, characters, min_len, max_len)
      if min_len && element.size < min_len
        raise BadNameException.new("Invalid #{name}: #{element}, must be at least #{min_len} characters")
      end

      if max_len && element.size > max_len
        raise BadNameException.new("Invalid #{name}: #{element}, must be at most #{max_len} characters")
      end

      if !element.strip(characters).empty?
        raise BadNameException.new("Invalid #{name}: #{element}, acceptable characters include: #{characters}")
      end
    end
  end
end
