module V1::Remote::Transport
  ANONYMOUS = Challenge["anonymous"]
  BASIC     = Challenge["basic"]
  BEARER    = Challenge["bearer"]

  private record Challenge, challenge : String do
    forward_missing_to @challenge

    def self.[](challenge)
      new(challenge)
    end

    def canonical
      @challenge = @challenge.downcase
      self
    end
  end
  private record PingResp, challenge : Challenge,
    # Following the challenge there are often key/value pairs
    # e.g. Bearer service="gcr.io",realm="https://auth.gcr.io/v36/tokenz"
    parameters : ::Hash(String, String),

    # The registry's scheme to use. Communicates whether we fell back to http.
    scheme : String do
    def initialize(@challenge, @scheme, @parameters = {} of String => String)
    end
  end

  protected def parse_challenge(suffix : String)
    kv = {} of String => String
    # Perform a simple check to see if scope contains some comma or not.
    # preference is to split on "," but this breaks when scope contains comma inside quotes
    cp = suffix.split(',')
    qp = suffix.split("\",")
    split = qp.size == cp.size - 1 ? qp : cp
    split.each do |token|
      token = token.strip

      parts = token.split('=', 2) # Break the token into a key/value pair
      if parts.size == 2
        kv[parts[0]] = parts[1].strip('"') # Unquote the value, if it is quoted.
      else
        kv[token] = "" # If there was only one part, treat is as a key with an empty value
      end
    end
    kv
  end

  private def ping(reg : Name::Registry, client : Cossack::Client) : PingResp
    # This first attempts to use "https" for every request, falling back to http
    # if the registry matches our localhost heuristic or if it is intentionally
    # set to insecure via name.NewInsecureRegistry.

    schemes = ["https"]
    schemes << "http" if reg.scheme == "http"
    conn_err = Exception.new("")
    schemes.each_with_index do |scheme, _|
      url = "#{scheme}://#{reg.reg_name}/v2/"
      begin
        client.headers["Content-Type"] = "application/json"
        client.headers["User-Agent"] = TRANSPORT_NAME
        resp = client.get(url)
      rescue exception
        conn_err = exception
        # potentially retry with http
        next
      end
      case
      when resp.success?
        return PingResp.new(challenge: ANONYMOUS, scheme: scheme)
      when resp.client_error? && resp.status == 401
        wac = resp.headers["WWW-Authenticate"]
        parts = wac.split(' ', 2)
        if parts.size == 2
          return PingResp.new(challenge: Challenge[parts[0]].canonical,
            parameters: parse_challenge(parts[1]),
            scheme: scheme)
        else
          return PingResp.new(challenge: Challenge[wac].canonical,
            scheme: scheme)
        end
      else
        raise "nrecognized HTTP status: #{resp.status}"
      end
    end
    raise conn_err
  end
end
