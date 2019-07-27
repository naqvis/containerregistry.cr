# Module Empty provides an implementation of v1.Image equivalent to "FROM scratch".
module V1::Empty
  # image is a singleton empty image, think: FROM scratch
  IMAGE = Random.image(0, 0)
  # INDEX is a singleton empty index, think FROM: scratch.
  INDEX = EmptyIndex.new
end

require "./*"
