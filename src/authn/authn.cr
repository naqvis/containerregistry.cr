# Module Authn defines different methods of authentication for talking to a container registry.
module Authn
  # Interface for providing User Credentials for use with a Docker Registry.
  abstract class Authenticator
    # Produces a value suitable for use in the Authorization header.
    abstract def authorization : String
  end

  # Singleton Authenticator for providing anonymous auth.
  ANONYMOUS = Anonymous.new
end

require "./*"
