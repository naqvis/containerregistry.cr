require "atomic"

module V1::Util
  class WaitGroup
    def initialize
      @count = Atomic(Int32).new(0)
      @span = Time::Span.new(nanoseconds: 5000)
    end

    def add(n = 1)
      @count.add n
    end

    def done
      add(-1)
    end

    def wait
      loop do
        return if @count.get == 0
        sleep(@span)
      end
    end
  end

  # A Group is a collection of fibers working on subtasks that are part of the same overall task.
  class Group
    @cancel : Proc(Void) | Nil
    @wg : WaitGroup
    property exception : Exception?

    def initialize
      @cancel = nil
      @wg = WaitGroup.new
      @exception = nil
      @exc_once = Once.new
    end

    def cancel
      @cancel
    end

    def cancel=(f : Proc(Void))
      @cancel = f
    end

    # wait blocks until all function calls from the Fiber method have returned, then
    # returns the first non-nil exception (if any) from them
    def wait
      @wg.wait
      if (c = @cancel)
        begin
          c.call
        rescue
        end
      end
      @exception
    end

    # spwan calls the given function in a new fiber.
    #
    # The first call to return a non-nil exception cancels the group; its exception will be
    # returned by wait
    def spawn(f : Proc(Void))
      @wg.add(1)
      proc = ->(o : Group, ex : Exception) do
        ->{
          o.exception = ex
          if (c = o.cancel)
            begin
              c.call
            rescue ex
              # do nothing
            end
          end
        }
      end
      spawn do
        f.call
      rescue ex
        @exc_once.do proc.call(self, ex)
        # @exc_once.do(->{
        #   @exception = ex
        #   if (c = @cancel)
        #     c.call
        #   end
        # })
      ensure
        @wg.done
      end
    end
  end
end
