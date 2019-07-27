require "json"
require "./hash"

module V1
  alias Duration = Int64

  # ConfigFile is the configuration file that holds the metadata describing
  # how to launch a container. See:
  # https:#github.com/opencontainers/image-spec/blob/master/config.md
  struct ConfigFile
    JSON.mapping(
      architecture: String,
      author: {type: String, nilable: true},
      container: {type: String, nilable: true},
      created: {type: Time, nilable: true},
      docker_version: {type: String, nilable: true},
      history: {type: Array(History), nilable: true},
      os: String,
      rootfs: RootFS,
      config: Config,
      container_config: {type: Config, nilable: true},
      os_version: {type: String, nilable: true},
    )

    def initialize(@rootfs, @config = Config.new, @architecture = "amd64", @os = "linux", @author = nil,
                   @container = nil, @created = nil, @docker_version = nil, @history = nil,
                   @container_config = nil, @os_version = nil)
    end
  end

  # History is one entry of a list recording how this container image was built.
  struct History
    JSON.mapping(
      author: {type: String, nilable: true},
      created: {type: Time, nilable: true},
      created_by: {type: String, nilable: true},
      comment: {type: String, nilable: true},
      empty_layer: {type: Bool, nilable: true},
    )

    def initialize(@author = "", @created = nil, @created_by = "", @comment = "", @empty_layer = false)
    end
  end

  # RootFS holds the ordered list of file system deltas that comprise the
  # container image's root filesystem.
  struct RootFS
    JSON.mapping(
      type: String,
      # diff_ids: {type: Array(V1::Hash), converter: V1::Hash}
      diff_ids: Array(String)
    )

    def initialize(@type, @diff_ids); end

    def diff_ids
      res = Array(V1::Hash).new(@diff_ids.size)
      @diff_ids.each_with_index do |d, _|
        res << V1::Hash.new(d)
      end
      res
    end

    def diff_ids=(arr : Array(V1::Hash))
      @diff_ids.clear
      arr.each do |d|
        @diff_ids << d.to_s
      end
    end
  end

  # HealthConfig holds configuration settings for the HEALTHCHECK feature.
  # Test is the test to perform to check that the container is healthy.
  # An empty slice means to inherit the default.
  # The options are:
  # {} : inherit healthcheck
  # {"NONE"} : disable healthcheck
  # {"CMD", args...} : exec arguments directly
  # {"CMD-SHELL", command} : run command with system's default shell
  struct HealthConfig
    JSON.mapping(
      test: {type: Array(String), nilable: true},
      # Zero means to inherit. Durations are expressed as integer nanoseconds.
      interval: {type: Duration, nilable: true},     # Interval is the time to wait between checks.
      timeout: {type: Duration, nilable: true},      # Timeout is the time to wait before considering the check to have hung.
      start_period: {type: Duration, nilable: true}, # The start period for the container to initialize before the retries starts to count down.

      # Retries is the number of consecutive failures needed to consider a container as unhealthy.
      # Zero means inherit.
      retries: {type: Int32, nilable: true}
    )
  end

  # Config is a submessage of the config file described as:
  #   The execution parameters which SHOULD be used as a base when running
  #   a container using the image.
  # The names of the fields in this message are chosen to reflect the JSON
  # payload of the Config as defined here:
  # https://git.io/vrAET
  # and
  # https:#github.com/opencontainers/image-spec/blob/master/config.md

  struct Config
    JSON.mapping(
      attach_stderr: {type: Bool, nilable: true},
      attach_stdin: {type: Bool, nilable: true},
      attach_stdou: {type: Bool, nilable: true},
      cmd: {type: Array(String), nilable: true},
      health_check: {type: HealthConfig, nilable: true},
      domain_name: {type: String, nilable: true},
      entry_point: {type: Array(String), nilable: true},
      env: {type: Array(String), nilable: true},
      hostname: {type: String, nilable: true},
      image: {type: String, nilable: true},
      labels: {type: ::Hash(String, String), nilable: true},
      on_build: {type: Array(String), nilable: true},
      open_stdin: {type: Bool, nilable: true},
      stdin_once: {type: Bool, nilable: true},
      tty: {type: Bool, nilable: true},
      volumes: {type: ::Hash(String, JSON::Any), nilable: true},
      working_dir: {type: String, nilable: true},
      exposed_ports: {type: ::Hash(String, JSON::Any), nilable: true},
      args_escaped: {type: Bool, nilable: true},
      network_disabled: {type: Bool, nilable: true},
      mac_address: {type: String, nilable: true},
      stop_signal: {type: String, nilable: true},
      shell: {type: Array(String), nilable: true}
    )

    def initialize; end
  end

  def self.parse_config_file(r : IO)
    str = r.gets_to_end

    ConfigFile.from_json(str)
  end
end
