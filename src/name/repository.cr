require "./registry"

module Name
  # Stores a docker repository name in a structured form.
  class Repository < Registry
    @repository : String
    @reg : Registry

    DEFAULT_NAMESPACE = "library"
    REPOSITORY_CHARS  = "abcdefghijklmnopqrstuvwxyz0123456789_-./"

    def initialize(name : String, @strict = false)
      if name.blank?
        raise BadNameException.new("A repository name must be specified")
      end
      domain = ""
      repo = name
      parts = name.split('/', 2)
      if parts.size == 2 && (parts[0].includes?('.') || parts[0].includes?(':'))
        # The first part of the repository is treated as the registry domain
        # iff it contains a '.' or ':' character, otherwise it is all repository
        # and the domain defaults to DockerHub.
        domain = parts[0]
        repo = parts[1]
      end
      super(domain, strict: @strict)
      @repository = repo
      check_repository(repo)
      if implicit_namespace? && @strict
        raise BadNameException.new "strict validation requires the full repository path (missing 'library')"
      end
      @reg = Registry.new domain, strict: @strict
    end

    # Returns the name from which the Repository was dervied.
    def to_s
      name
    end

    def name
      base = reg_name
      if !base.blank?
        "#{base}/#{repo_str}"
      else
        repo_str
      end
    end

    # Returns the repository component of the Repository
    def repo_str
      if implicit_namespace?
        "#{DEFAULT_NAMESPACE}/#{@repository}"
      else
        @repository
      end
    end

    def registry
      @reg
    end

    # scope returns the scope required to perform the given action on the registry.
    def scope(action)
      "repository:#{repo_str}:#{action}"
    end

    def identifier
      @repository
    end

    def as_repository
      self
    end

    def_equals_and_hash @repository, @strict

    # See https://docs.docker.com/docker-hub/official_repos
    private def implicit_namespace?
      !@repository.includes?('/') && reg_name == DEFAULT_REGISTRY
    end

    private def check_repository(repo)
      check_element("repository", repo, REPOSITORY_CHARS, 2, 255)
    end
  end
end
