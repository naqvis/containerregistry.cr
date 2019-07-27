module V1::Types
  record MediaType, str : String do
    forward_missing_to @str

    def self.[](str)
      new(str)
    end

    def self.new(pull : JSON::PullParser)
      pull.read_string
    end

    def self.from_json(pull : JSON::PullParser)
      string = pull.read_string
      self[string]
    end

    def self.to_json(json : JSON::Builder)
      json.string(self.to_s)
    end

    def self.to_json(mtype : MediaType, json : JSON::Builder)
      json.string(mtype.to_s)
    end

    def to_s
      @str
    end
  end

  OCICONTENTDESCRIPTOR           = MediaType["application/vnd.oci.descriptor.v1+json"]
  OCIIMAGEINDEX                  = MediaType["application/vnd.oci.image.index.v1+json"]
  OCIMANIFESTSCHEMA1             = MediaType["application/vnd.oci.image.manifest.v1+json"]
  OCICONFIGJSON                  = MediaType["application/vnd.oci.image.config.v1+json"]
  OCILAYER                       = MediaType["application/vnd.oci.image.layer.v1.tar+gzip"]
  OCIRESTRICTEDLAYER             = MediaType["application/vnd.oci.image.layer.nondistributable.v1.tar+gzip"]
  OCIUNCOMPRESSEDLAYER           = MediaType["application/vnd.oci.image.layer.v1.tar"]
  OCIUNCOMPRESSEDRESTRICTEDLAYER = MediaType["application/vnd.oci.image.layer.nondistributable.v1.tar"]

  DOCKERMANIFESTSCHEMA1       = MediaType["application/vnd.docker.distribution.manifest.v1+json"]
  DOCKERMANIFESTSCHEMA1SIGNED = MediaType["application/vnd.docker.distribution.manifest.v1+prettyjws"]
  DOCKERMANIFESTSCHEMA2       = MediaType["application/vnd.docker.distribution.manifest.v2+json"]
  DOCKERMANIFESTLIST          = MediaType["application/vnd.docker.distribution.manifest.list.v2+json"]
  DOCKERLAYER                 = MediaType["application/vnd.docker.image.rootfs.diff.tar.gzip"]
  DOCKERCONFIGJSON            = MediaType["application/vnd.docker.container.image.v1+json"]
  DOCKERPLUGINCONFIG          = MediaType["application/vnd.docker.plugin.v1+json"]
  DOCKERFOREIGNLAYER          = MediaType["application/vnd.docker.image.rootfs.foreign.diff.tar.gzip"]
  DOCKERUNCOMPRESSEDLAYER     = MediaType["application/vnd.docker.image.rootfs.diff.tar"]
end

require "json"
