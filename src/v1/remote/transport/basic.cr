require "cossack"
require "../../../authn"

module V1::Remote::Transport
  abstract class AuthHandler
    abstract def client : Cossack::Client
  end

  class Anonymous < AuthHandler
    getter client : Cossack::Client

    def initialize(@client)
    end
  end

  class Basic < AuthHandler
    getter client : Cossack::Client
    getter auth : Authn::Authenticator
    getter target : String?

    def initialize(@client, @auth, @target)
      @client.use BasicAuth, basic: self
    end

    def initialize(@auth, @target)
      @client = Cossack::Client.new
      @client.use BasicAuth, basic: self
    end

    private class BasicAuth < Cossack::Middleware
      @basic : Basic

      def initialize(@app, @basic)
        super(@app)
      end

      def call(request : Cossack::Request) : Cossack::Response
        hdr = @basic.auth.authorization
        # To avoid forwarding Authorization headers to places
        # we are redirected, only set it when the authorization header matches
        # the host with which we are interacting.
        # In case of redirect Client can use an empty Host, check URL too.
        request.headers["Authorization"] = hdr unless request.uri.host != @basic.target
        request.headers["User-Agent"] = TRANSPORT_NAME
        app.call(request)
      end
    end
  end
end
