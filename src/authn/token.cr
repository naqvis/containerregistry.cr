require "./authn"

# Implementation for providing a transaction's X-Docker-Token as creds.
class Authn::Token < Authn::Authenticator
  def initialize(@token : String)
  end

  def authorization
    "Token #{@token}"
  end
end
