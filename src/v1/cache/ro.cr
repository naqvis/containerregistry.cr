module V1::Cache
  # ReadOnly returns a read-only implementation of the given Cache.
  # put and delete operations are a no-op
  class ReadOnly < Cacher
    @cache : Cacher

    def initialize(@cache)
    end

    def put(l : V1::Layer)
      l
    end

    def get(h : V1::Hash)
      @cache.get h
    end

    def delete(h : V1::Hash)
    end
  end
end
