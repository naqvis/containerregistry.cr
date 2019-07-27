require "json"
require "./authn"

# Bearer implements Authenticator for bearer authentication.
class Authn::Bearer < Authn::Authenticator
  JSON.mapping(
    token: String
  )

  def initialize(@token : String)
  end

  def authorization
    "Bearer #{token}"
  end
end
