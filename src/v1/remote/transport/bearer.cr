require "cossack"
require "http"
require "json"
require "uri"
require "../../../authn"
require "../../../name"

module V1::Remote::Transport
  class Bearer < AuthHandler
    getter client : Cossack::Client
    # Basic credentials that we exchange for bearer tokens.
    @basic : Authn::Authenticator
    # Holds the bearer response from the token service.
    getter bearer : Authn::Bearer
    # Registry to which we send bearer tokens.
    getter registry : Name::Registry
    # See https://tools.ietf.org/html/rfc6750#section-3
    getter realm : String
    # See https://docs.docker.com/registry/spec/auth/token/
    @service : String
    getter scopes : Array(String)
    # Scheme we should use, determined by ping response.
    getter scheme : String

    def initialize(@client, @basic, @registry, @realm, @service, @scopes, @scheme, @bearer = Authn::Bearer.new(""))
      @client.use BearerAuth, bt: self
    end

    private def set_bearer(bearer)
      @bearer = bearer
    end

    def update(resp)
      return unless resp.status == 401
      if (wac = resp.headers["WWW-Authenticate"]?)
        parts = wac.split(' ', 2)
        if parts.size == 2
          c = Challenge[parts[0]].canonical
          return unless c == BEARER
          pr = Transport.parse_challenge(parts[1])
          @service = pr.fetch("service", @service)
          @realm = pr.fetch("realm", @realm)
          # If the scope parameter is not specified, then default it to passed scopes
          # parameter, else replace that with bearer challenged provided one
          if (s = pr["scope"]?)
            @scopes = [s]
          end
        end
      end
    end

    def refresh
      uri = URI.parse(@realm)
      client = Cossack::Client.new do |c|
        c.use StdoutLogger
        c.use Cossack::CookieJarMiddleware, cookie_jar: c.cookies
        c.use RedirectionMiddleware
      end
      Basic.new(client, @basic, uri.host)

      params = ::Hash{"scope"   => @scopes,
                      "service" => [@service]}
      query = IO::Memory.new
      HTTP::Params.new(params).to_s(query)
      auth_uri = URI.new(host: uri.host, port: uri.port, scheme: uri.scheme, query: query.to_s, path: uri.path)

      resp = client.get auth_uri.to_s

      err = Transport.check_error(resp, 200)
      raise err unless err.nil?

      begin
        response = TokenResponse.from_json(resp.body)
      rescue exception
        # Some registries don't have "token" in the response.
        raise exception
      end
      # Find a token to turn into a Bearer authenticator
      if !response.token.blank?
        bearer = Authn::Bearer.new(response.token)
      elsif !response.access_token.blank?
        bearer = Authn::Bearer.new(response.access_token)
      else
        raise "no token in bearer response:\n #{resp.body}"
      end
      # Replace our old bearer authenticator (if we had one) with our newly refreshed authenticator.
      set_bearer(bearer)
    end

    private struct TokenResponse
      JSON.mapping(
        token: {type: String, default: ""},
        access_token: {type: String, default: ""}
      )
    end

    private class BearerAuth < Cossack::Middleware
      @bt : Bearer

      def initialize(@app, @bt)
        super(@app)
      end

      def call(request : Cossack::Request) : Cossack::Response
        send_request = ->{
          hdr = @bt.bearer.authorization
          # To avoid forwarding Authorization headers to places
          # we are redirected, only set it when the authorization header matches
          # the host with which we are interacting.
          # In case of redirect Client can use an empty Host, check URL too.
          if request.uri.host == @bt.registry.registry
            request.headers["Authorization"] = hdr
            request.uri.scheme = @bt.scheme
          end
          request.headers["User-Agent"] = TRANSPORT_NAME
          app.call(request)
        }
        resp = send_request.call
        # Perform a token refresh() and retry the request in case the token has expired
        if resp.client_error? && resp.status == 401
          @bt.update resp
          @bt.refresh
          return send_request.call
        end
        resp
      end
    end
  end
end
