class Range
  ##
  # :call-seq:
  #   rng.each { |i| block }  => rng
  #
  # Iterates over the elements +rng+, passing each in turn to the block. You
  # can only iterate if the start object of the range supports the
  # succ method (which means that you can't iterate over ranges of
  # Float objects).
  #
  #   (10..15).each do |n|
  #      print n, ' '
  #   end
  #
  # produces:
  #
  #   10 11 12 13 14 15

  def each(&block)
    return to_enum unless block_given?
    first, last = @begin, @end # dup?

    raise TypeError, "can't iterate from #{first.class}" unless first.respond_to? :succ

    if first.is_a?(Fixnum) && last.is_a?(Fixnum)
      last -= 1 if self.exclude_end?
      first.upto(last, &block)
    elsif first.is_a?(String)
      first.upto(last) do |s|
        yield s unless @excl && s == last
      end
    else
      current = first
      if @excl then
        while (current <=> last) < 0
          yield current
          current = current.succ
        end
      else
        while (c = current <=> last) && c <= 0
          yield current
          break if c == 0
          current = current.succ
        end
      end
    end
    return self
  end

  ##
  # :call-seq:
  #   rng.step(n = 1) { |obj| block }  => rng
  #
  # Iterates over +rng+, passing each +n+th element to the block. If the range
  # contains numbers or strings, natural ordering is used. Otherwise
  # +step+ invokes +succ+ to iterate through range elements. The following
  # code uses class Xs, which is defined in the class-level documentation.
  #
  #   range = Xs.new(1)..Xs.new(10)
  #   range.step(2) { |x| puts x }
  #   range.step(3) { |x| puts x }
  #
  # produces:
  #
  #    1 x
  #    3 xxx
  #    5 xxxxx
  #    7 xxxxxxx
  #    9 xxxxxxxxx
  #    1 x
  #    4 xxxx
  #    7 xxxxxxx
  #   10 xxxxxxxxxx

  def step(step_size = 1, &block) # :yields: object
    return to_enum :step, step_size unless block_given?
    first, last = @begin, @end
    step_size = (Float === first) ? Float(step_size) : Integer(step_size)

    raise ArgumentError, "step can't be negative" if step_size < 0
    raise ArgumentError, "step can't be 0" if step_size == 0

    if step_size == 1
      each(&block)
    elsif first.kind_of?(Numeric)
      cmp_method = self.exclude_end? ? :< : :<=

      while first.__send__(cmp_method, last)
        block.call(first)
        first += step_size
      end
    else
      counter = 0
      each do |o|
        block.call(o) if counter % step_size == 0
        counter += 1
      end
    end

    return self
  end

end