module V1::Remote::Transport
  # Scopes suitable to qualify each Repository
  PULL_SCOPE = "pull"
  PUSH_SCOPE = "push,pull"
  # For now DELETE is PUSH, which is the read/write ACL.
  DELETE_SCOPE  = PUSH_SCOPE
  CATALOG_SCOPE = "catalog"
end
