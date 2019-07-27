require "json"

# Represents runtime requirements for an image.
# See: https://docs.docker.com/registry/spec/manifest-v2-2/#manifest-list
struct V1::Platform
  JSON.mapping(
    architecture: String,
    os: String,
    os_version: {type: String, key: "os.version", nilable: true},
    os_features: {type: Array(String), key: "os.features", default: [] of String},
    variant: {type: String, nilable: true},
    features: {type: Array(String), default: [] of String},
  )

  def initialize(@architecture = "amd64", @os = "linux", @os_features = [] of String, @features = [] of String)
  end

  def can_run(required : self)
    return true if required.nil?

    if required.architecture != architecture ||
       required.os != os ||
       (required.os_version && required.os_version != os_version)
      (required.variant && required.variant != variant) ||
        (required.os_features && !(required.os_features.to_set.subset? os_features.to_set)) ||
        (required.features && !(required.features.to_set.subset? features.to_set))
      return false
    end
    true
  end

  def compatible_with(target : self)
    target.can_run(self)
  end
end
