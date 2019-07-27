require "json"
require "../name/registry"
require "./authn"

module Authn
  # Interface for resolving an image reference to a credential.
  abstract class Keychain
    # Resolves the appropriate credential for the given registry.
    # Args:
    #   name: the registry for which we need a credential.

    # Returns:
    #   a Provider suitable for use with registry operations.
    abstract def resolve(registry : Name::Registry) : Authn::Authenticator
  end

  class DefaultKeychain < Keychain
    FORMATS = [
      # Allow naked domains
      "%s",
      # Allow scheme-prefixed.
      "https://%s",
      "http://%s",
      # Allow scheme-prefixes with version in url path.
      "https://%s/v1/",
      "http://%s/v1/",
      "https://%s/v2/",
      "http://%s/v2/",
    ]

    private class AuthEntry
      JSON.mapping(
        auth: {type: String, nilable: true},
        username: {type: String, nilable: true},
        password: {type: String, nilable: true},
      )
    end

    private class Cfg
      JSON.mapping(
        cred_helper: {type: Hash(String, String), key: "credHelpers", nilable: true},
        cred_store: {type: String, key: "credsStore", nilable: true},
        auths: {type: Hash(String, AuthEntry), nilable: true}
      )
    end

    def resolve(registry : Name::Registry) : Authenticator
      contents = File.read(get_config_file)
    rescue exception
      Authn::ANONYMOUS
    else
      begin
        cfg = Cfg.from_json(contents)
      rescue exception
        # Unable to parse contents
        Authn::ANONYMOUS
      else
        parse_cfg(cfg, registry)
      end
    end

    private def parse_cfg(cfg : Cfg, reg : Name::Registry)
      if cfg.nil? || reg.nil?
        return Authn::ANONYMOUS
      end

      # Per-registry credential helpers take precedence.
      if creds = cfg.cred_helper
        FORMATS.each_with_index do |f, _|
          if v = creds[f % reg.registry]?
            return Authn::Helper.new(v, reg)
          end
        end
      end

      # A global credential helper is next in precedence.
      if store = cfg.cred_store
        return Authn::Helper.new(store, reg)
      end

      # Lastly, the 'auths' section directly contains basic auth entries.
      if auths = cfg.auths
        FORMATS.each_with_index do |f, _|
          if entry = auths[f % reg.registry]?
            user = entry.username
            passwd = entry.password
            if a = entry.auth
              return Authn::Auth.new(a) if a.empty?
            end
            return Authn::Basic.new(user, passwd) if user && passwd

            # TODO(user): Support identitytoken
            # TODO(user): Support registrytoken
            raise Exception.new("Unsupported entry in \"auth\" section of Docker config: #{entry.to_json}")
          end
        end
      end
      ANONYMOUS
    end

    # %HOME% has precedence over %USERPROFILE% for os.path.expanduser("~")
    # The Docker config resides under %USERPROFILE% on Windows
    private def get_docker_home
      {% if flag?(:win32) %}
      Path["%USERPROFILE%"].expand
    {% else %}
      Path.home
    {% end %}
    end

    # Return the value of $DOCKER_CONFIG, if it exists, otherwise ~/.docker
    # see https://github.com/docker/docker/blob/master/cliconfig/config.go
    private def get_config_dir
      ENV.fetch("DOCKER_CONFIG", nil) || get_docker_home.join(".docker").to_s
    end

    private def get_config_file
      Path.new(get_config_dir, "config.json")
    end
  end
end
