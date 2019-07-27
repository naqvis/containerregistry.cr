require "cossack"
require "../../authn"
require "../../authn/anon"
require "../../authn/keychain"
require "../platform"
require "../../name/registry"

module V1::Remote
  extend self

  private class Options
    property auth : Authn::Authenticator
    property keychain : Authn::Keychain
    property client : Cossack::Client
    property platform : V1::Platform

    def initialize(@auth = Authn::ANONYMOUS,
                   @keychain = Authn::DefaultKeychain.new,
                   @client = Cossack::Client.new,
                   @platform = V1::Platform.new)
    end
  end

  alias Option = Proc(Options, Nil)

  # functional option for overriding default transport for remote operations
  def with_transport(t : Cossack::Client)
    Option.new { |o| o.client = t }
  end

  # functional option for overriding the default authenticator for remove operations
  # The default authenticator is Authn::Anonymous
  def with_auth(auth : Authn::Authenticator)
    Option.new { |o| o.auth = auth }
  end

  # functional option for overriding the default authenticator for remote operations,
  # using an Authn::KeyChain to find credentials
  #
  # The default authenticator is Authn::Anonymous
  def with_auth_from_keychain(keys : Authn::Keychain)
    Option.new { |o| o.keychain = keys }
  end

  # a functional option for overriding the default platform that Image and
  # Descriptor.Image use for resolving an index to an image.
  #
  # The default platform is amd64/linux
  def with_platform(p : V1::Platform)
    Option.new { |o| o.platform = p }
  end

  protected def make_options(reg : Name::Registry, *opts : Option)
    client = Cossack::Client.new do |c|
      c.use Cossack::CookieJarMiddleware, cookie_jar: c.cookies
      c.use Transport::StdoutLogger
      c.use Transport::RedirectionMiddleware
    end
    o = Options.new(client: client)

    opts.each do |opt|
      opt.call(o)
    end

    o.keychain.try do |kc|
      auth = kc.resolve reg
      if auth.is_a?(Authn::Anonymous)
        V1::Logger.info "No matching credentials were found, falling back on anonymous"
      end
      o.auth = auth
    end
    o
  end
end
