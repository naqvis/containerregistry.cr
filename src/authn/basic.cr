require "json"
require "base64"
require "./authn"

# Basic implements Authenticator for basic authentication.
class Authn::Basic < Authn::Authenticator
  JSON.mapping(
    username: {type: String, key: "Username"},
    password: {type: String, key: "Secret"},
  )

  def initialize(@username : String, @password : String)
  end

  def authorization
    delimited = "#{@username}:#{@password}"
    encoded = Base64.strict_encode(delimited)
    "Basic #{encoded}"
  end
end
