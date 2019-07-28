module V1::Remote::Transport
  extend self
  TRANSPORT_NAME = "crystal-containerregistry"
  class_property verbose_http = false

  class StdoutLogger < Cossack::Middleware
    def call(request : Cossack::Request) : Cossack::Response
      return app.call(request) unless Transport.verbose_http
      puts V1::Util.dump_request(request, false)
      app.call(request).tap do |response|
        puts V1::Util.dump_response(response, false)
      end
    end
  end

  class RedirectionMiddleware < Cossack::Middleware
    @limit : Int32

    def initialize(@app, limit : Number = 5)
      @limit = limit.to_i
    end

    def call(request : Cossack::Request) : Cossack::Response
      current_request = request
      count = 0
      response = app.call(request)

      method, should_redirect, include_body = redirect_behavior(request, response)
      while should_redirect && count < @limit
        count += 1
        V1::Logger.debug "Redirecting #{count}" if Transport.verbose_http
        redirect_uri = URI.parse(response.headers["Location"])
        merge_uri!(redirect_uri, current_request.uri)
        current_request = Cossack::Request.new(method, redirect_uri, current_request.headers,
          include_body ? request.body : nil, current_request.options)
        response = app.call(current_request)
        method, should_redirect, include_body = redirect_behavior(current_request, response)
      end

      response
    end

    private def redirect_behavior(req, res)
      method = req.method
      should_redirect = false
      include_body = false
      case res.status
      when 301, 302, 303
        should_redirect = true

        # RFC 2616 allowed automatic redirection only with GET and
        # HEAD requests. RFC 7231 lifts this restriction, but we still
        # restrict other methods to GET to maintain compatibility.
        # See Issue 18570.
        method = "GET" if method != "GET" && method != "HEAD"
      when 307, 308
        should_redirect = true
        include_body = true

        # Treat 307 and 308 specially, they also require re-sending the request body
        if res.headers.has_key?("Location") && res.headers["Location"].blank?
          # 308s have been observed in the wild being served without
          # Location headers. Just stop here instead of returning an error.
          should_redirect = false
        end
      end

      {method, should_redirect, include_body}
    end

    private def merge_uri!(redirect_uri, original_uri)
      # Unless it is absolute URL
      unless redirect_uri.host
        redirect_uri.host ||= original_uri.host
        redirect_uri.scheme ||= original_uri.scheme
        redirect_uri.port ||= original_uri.port
        redirect_uri.user ||= original_uri.user
        redirect_uri.password ||= original_uri.password

        # If path is relative
        unless redirect_uri.path.to_s.starts_with? '/'
          # Remove last part in path, e.g. "/users/13" => "/users/"
          base_path = original_uri.path.to_s.sub(%r{/[^/]+$}, "/")
          redirect_uri.path = File.join(base_path, redirect_uri.path.to_s)
        end
      end
    end
  end

  # Returns transport based on the provided client that has
  # been setup to authenticate with the remote registry "reg", in the capacity
  # laid out by the specified scopes.

  def new_transport(reg : Name::Registry, auth : Authn::Authenticator, client : Cossack::Client,
                    scopes : Array(String))
    # The handshake:
    #  1. Use "t" to ping() the registry for the authentication challenge.
    #
    #  2a. If we get back a 200, then simply use "t".
    #
    #  2b. If we get back a 401 with a Basic challenge, then use a transport
    #     that just attachs auth each roundtrip.
    #
    #  2c. If we get back a 401 with a Bearer challenge, then use a transport
    #     that attaches a bearer token to each request, and refreshes is on 401s.
    #     Perform an initial refresh to seed the bearer token.

    # First we ping the registry to determine the parameters of the authentication handshake
    # (if one is even necessary).

    pr = ping(reg, client)
    case pr.challenge.canonical
    when ANONYMOUS
      Anonymous.new(client)
    when BASIC
      Basic.new(client, auth, reg.reg_name)
    when BEARER
      # We require the realm, which tells us where to send our Basic auth to turn it into Bearer auth.
      raise "malformed www-authenticate, missing realm" unless pr.parameters.has_key?("realm")

      # If the service parameter is not specified, then default it to the registry
      # with which we are talking
      service = pr.parameters.fetch("service", reg.to_s)

      # If the scope parameter is not specified, then default it to passed scopes
      # parameter, else replace that with bearer challenged provided one
      scope = pr.parameters["scope"]?
      if (s = scope)
        scopes = [s]
      end

      bt = Bearer.new(client: client, basic: auth, realm: pr.parameters["realm"], registry: reg,
        service: service, scopes: scopes, scheme: pr.scheme)

      bt.refresh
      bt
    else
      raise "Unrecognized challenge: #{pr.challenge}"
    end
  end
end

require "./*"
