require "./repository"
require "./tag"
require "./ref"

module Name
  # Stores a docker repository digest in a structured form
  class Digest < Repository
    # These have the form: sha256:<hex string>
    DIGEST_CHARS = "sh:0123456789abcdef"
    @digest : String
    @repo : Repository

    def initialize(name : String, @strict = true)
      parts = name.split('@', 2)
      if parts.size != 2
        raise BadNameException.new("a digest must contain exactly one '@' separator (e.g. registry/repository@digest) saw: #{name}")
      end
      base = parts[0]
      @digest = parts[1]

      # Always check that the digest is valid.
      check_digest(@digest)
      begin
        tag = Tag.new base, strict: @strict
      rescue ex
      else
        base = tag.as_repository.name
      end
      super(base, strict: @strict)
      @repo = Repository.new base, strict: @strict
    end

    def to_s
      name
    end

    # Construct a new Repository object from the string representation
    # our parent class (Repository) produces.  This is a convenience
    # method to allow consumers to stringify the repository portion of
    # a tag or digest without their own format string.
    # We have already validated, and we don't persist strictness.
    def as_repository
      @repo
    end

    def identifier
      @digest
    end

    # returns the digest component of the Digest
    def digest
      @digest
    end

    def name
      "#{super}@#{@digest}"
    end

    def_equals_and_hash @digest, @strict

    private def check_digest(digest)
      check_element("digest", digest, DIGEST_CHARS, 7 + 64, 7 + 64)
    end
  end
end
