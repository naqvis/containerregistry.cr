require "./repository"

module Name
  module Reference
    # Context accesses the Repository context of the reference.
    abstract def as_repository : Repository
    # Identifier accesses the type-specific portion of the reference.
    abstract def identifier : String
    # Name is the fully-qualified reference name.
    abstract def name : String
    # Scope is the scope needed to access this reference.
    abstract def scope(action : String) : String

    def self.parse_reference(str : String, strict = false)
      [Name::Tag, Name::Digest].each_with_index do |cls, _|
        begin
          return cls.new(str)
        rescue ex
        end
      end
      raise Exception.new("'#{str}' is not a valid Tag or Digest")
    end
  end
end

require "./tag"
require "./digest"
