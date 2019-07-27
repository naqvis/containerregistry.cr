require "./authn"

# auth implements Authenticator for an "auth" entry of the docker config.
class Authn::Auth < Authn::Authenticator
  def initialize(@token : String)
  end

  def authorization
    "Basic #{@token}"
  end
end
