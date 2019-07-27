require "./authn"

# anonymous implements Authenticator for anonymous authentication.
class Authn::Anonymous < Authn::Authenticator
  def initialize
  end

  # Implement anonymous authentication.
  def authorization
    ""
  end
end
