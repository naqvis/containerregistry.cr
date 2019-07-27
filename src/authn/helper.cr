require "./basic"
require "../name/registry"

# This provider wraps a particularly named credential helper.
class Authn::Helper < Authn::Authenticator
  MAGIC_NOT_FOUND_MESSAGE = "credentials not found in native keychain"
  getter registry : String

  # Args:
  #  name: the name of the helper, as it appears in the Docker config.
  #  registry: the registry for which we're invoking the helper.
  def initialize(@name : String, registry : Name::Registry)
    @registry = registry.reg_name
  end

  def authorization
    # Invokes:
    #   echo -n {self._registry} | docker-credential-{self._name} get
    #   The resulting JSON blob will have 'Username' and 'Secret' fields.

    command = "docker-credential-#{@name}"
    has_command = Process.run("command -v #{command}", shell: true).success?
    if !has_command
      raise Exception.new("executable not found: #{command}")
    end

    output = IO::Memory.new
    reg = "https://#{@registry}"
    input = IO::Memory.new(reg)
    status = Process.run(command, ["get"], input: input, output: output)
    msg = output.to_s
    if status.success?
      Authn::Basic.from_json(msg).authorization
    else
      if msg.strip == MAGIC_NOT_FOUND_MESSAGE
        V1::Logger.info "Credentials not found, falling back to anonymous auth."
        Authn::ANONYMOUS.authorization
      else
        raise Exception.new("Error fetching credential for #{@registry}, exit status: #{status.exit_code}\n#{msg}")
      end
    end
  end
end
