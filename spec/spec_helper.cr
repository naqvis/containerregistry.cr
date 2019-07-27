require "spec"
require "../src/**"

def must_hash(s : String)
  h, _ = V1::Hash.sha256(IO::Memory.new(s))
  h
end
