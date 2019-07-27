# Module Stream provides streaming implementation of V1::Layer
module V1::Stream
  # ExNotComputed is returned when the requested value is not yet
  # computed because the stream has not been consumed yet
  class ExNotComputed < Exception
  end

  # ExConsumed is returned by Compressed when the underlying stream has
  # already been consumed and closed.
  class ExConsumed < Exception
  end
end

require "./*"
