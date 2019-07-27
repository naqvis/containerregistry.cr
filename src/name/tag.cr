require "./repository"
require "./ref"

module Name
  # Stores a docker repository tag in a structured form.
  class Tag < Repository
    # include Name::Reference

    TAG_CHARS   = "abcdefghijklmnopqrstuvwxyz0123456789_-.ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    DEFAULT_TAG = "latest"

    @tag : String = ""
    @repo : Repository

    def initialize(name : String, @strict = false)
      base = name
      tag = ""
      parts = name.split(':')
      # Verify that we aren't confusing a tag for a hostname w/ port for the purposes of weak validation.
      if parts.size > 1 && !parts[parts.size - 1].includes?("/")
        base = parts[0, parts.size - 1].join(":")
        tag = parts[parts.size - 1]
      end

      # We don't require a tag, but if we get one check it's valid,
      # even when not being strict.
      # If we are being strict, we want to validate the tag regardless in case
      # it's empty.
      if @strict || !tag.blank?
        check_tag(tag)
      end
      super(base, strict: @strict)
      @tag = tag
      @repo = Repository.new base, strict: @strict
    end

    def tag
      @tag.blank? ? DEFAULT_TAG : @tag
    end

    def to_s
      name
    end

    def identifier
      tag
    end

    def name
      "#{super}:#{tag}"
    end

    # scope returns teh scope required to perform the given action on the tag.
    def scope(action : String)
      super
    end

    # Construct a new Repository object from the string representation
    # our parent class (Repository) produces.  This is a convenience
    # method to allow consumers to stringify the repository portion of
    # a tag or digest without their own format string.
    # We have already validated, and we don't persist strictness.
    def as_repository
      @repo
    end

    def_equals_and_hash @tag, @strict

    private def check_tag(tag)
      check_element("tag", tag, TAG_CHARS, 1, 127)
    end
  end
end
