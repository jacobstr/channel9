# depends on: class.rb numeric.rb regexp.rb string.rb

def BigDecimal(string, _precs=0)
  BigDecimal.new(string, _precs)
end

class BigDecimal < Numeric
  # See stdlib/ext/bigdecimal for MatzRuby implementation.
  
  attr_reader :digits
  protected :digits
  
  #############
  # Constants #
  #############
  
  SIGN_POSITIVE_ZERO = 1
  SIGN_NEGATIVE_ZERO = -1
  SIGN_POSITIVE_FINITE = 2
  SIGN_NEGATIVE_FINITE = -2
  SIGN_POSITIVE_INFINITE = 3
  SIGN_NEGATIVE_INFINITE = -3
  SIGN_NaN = 0 # is this correct?
  
  PLUS = '+'
  MINUS = '-'
  RADIX = '.'
  EXP = 'E'
  
  # call-seq:
  #   BigDecimal("3.14159")   => big_decimal
  #   BigDecimal("3.14159", 10)   => big_decimal
  def initialize(_val, _precs=0)
    # set up defaults
    @sign = PLUS
    @digits = 0 # decimal point is assumed at beginning; exp is assigned on this basis
    @exp = 0
    @special = nil # 'n' for NaN, 'i' for Infinity, nil otherwise

    v = _val.strip
    if v == "NaN"
      @special = 'n'
      @precs = 0
    elsif v =~ /[-+]?Infinity/
      @special = 'i'
      @sign = MINUS if v =~ /-/
      @precs = 0
    else
      v = _val.gsub('_', '')
      m = /^\s*(([-+]?)(\d*)(?:\.(\d*))?(?:[EeDd]([-+]?\d+))?).*$/.match(v)
      if !m.nil?
        @sign = m[2] unless m[2].to_s.empty?
        int = m[3].to_s.gsub(/^0*/, '')
        frac = m[4].to_s
        fraczeros = /^0*/.match(frac)[0]
        @exp = m[5].to_i + int.length
        if int.to_i == 0 
          @exp -= fraczeros.length
        end
        @digits = (int + frac).gsub(/0*$/, '').to_i
      end
      @precs = [v.length, _precs].max
    end
  end

  # As for Float.finite? .
  # call-seq:
  #   BigDecimal.new("Infinity").finite?  => false
  #   BigDecimal.new("NaN").finite?  => true
  def finite?
    @special != 'i'
  end
  
  def infinite?
    if self.finite?
      return nil
    else
      return (@sign + '1').to_i
    end
  end

  # As for Float.nan? .
  # call-seq:
  #   BigDecimal.new("NaN").nan?  => true
  #   BigDecimal.new("123").nan?  => false
  def nan?
    @special == 'n'
  end
  
  # True if positive or negative zero; false otherwise.
  # call-seq:
  #   BigDecimal.new("0").zero?   =>true
  #   BigDecimal.new("-0").zero?  =>true
  def zero?
    @digits.to_i == 0 and !self.nan? and self.finite?
  end

  def precs
    if !self.finite? or self.nan?
      sigfigs = 0
    else
      sigfigs = @digits.to_s.length
    end
    [sigfigs, @precs]
  end
  
  ###############
  # Conversions #
  ###############
  
  def to_f
    self.to_s("F").to_f
    # Are there more cases we need to trap for?  This seems too easy.
  end
  
  def to_i
    if self.nan? or !self.finite?
      return nil
    end
    self.fix.to_s("F").to_i
  end

  def to_s(arg='')
    # parse the argument for format specs
    positive = case arg
      when /\+/ then PLUS.clone
      when / / then ' '
      else ''
    end
    format = arg =~ /F/ ? :float : :eng
    spacing = arg.to_i
    
    nan = 'NaN'
    infinity = 'Infinity'

    if self.nan?
      return nan
    end

    if @sign == PLUS
      str = positive
    else
      str = MINUS.clone
    end

    if self.finite?
      value = @digits.to_s
      if format == :float
        # get the decimal point in place
        if @exp >= value.length
          value << ('0' * (@exp - value.length)) + RADIX + '0'
        elsif @exp > 0
          value = value[0, @exp] + RADIX + value[@exp..-1]
        elsif @exp <= 0
          value = '0' + RADIX + ('0' * -@exp) + value
        end
      elsif format == :eng
        value = '0' + RADIX + value
        if @exp != 0
          value << EXP + @exp.to_s
        end
      end
      
      if spacing != 0
        m = /^(\d*)(?:(#{RADIX})(\d*)(.*))?$/.match(value)
        left, myradix, right, extra = m[1, 4].collect{|s| s.to_s}
        right_frags = []
        0.step(right.length, spacing) do |n|
          right_frags.push right[n, spacing]
        end
        
        left_frags = []
        tfel = left.reverse
        0.step(left.length, spacing) do |n|
          left_frags.unshift tfel[n, spacing].reverse
        end
        
        right = right_frags.join(' ').strip
        left = left_frags.join(' ').strip
        value = left.to_s + myradix.to_s + right.to_s + extra.to_s
      end
      str << value
    else
      str << infinity
    end
    return str
  end
  
  def inspect
    str = '#<BigDecimal:'
    str << [nil, "'#{self.to_s}'", "#{precs[0]}(#{precs[1]})"].join(',')
    str << '>'
    return str
  end

  def coerce(other)
    Ruby.primitive :numeric_coerce
    if other.kind_of?(BigDecimal)
      [other, self]
    else
      [BigDecimal(other.to_s), self]
    end
  end

  #########################
  # Arithmetic operations #
  #########################

  # These are stubbed out until we implement them so that their respective specfiles don't crash.

  def +(other)
    signs = {SIGN_POSITIVE_FINITE => 1, SIGN_NEGATIVE_FINITE => -1}
    if self.nan? or other.nan?
      return BigDecimal("NaN")
    elsif !self.finite? and !other.finite? and self.sign != other.sign
      # infinity + -infinity
      return BigDecimal("NaN")
    elsif !self.finite?
      return self
    elsif !other.finite?
      return other
    elsif self.exponent == other.exponent
      sd = self.digits.to_s
      od = other.digits.to_s
      diff = sd.length - od.length
      if diff > 0
        od << '0' * diff
      else
        sd << '0' * diff.abs
      end
      sum = (sd.to_i * signs[self.sign]) + (od.to_i * signs[other.sign])
      s = sum.abs.to_s
      sumdiff = s.length - sd.length
      if sum < 0
        s = MINUS + RADIX + s
      else
        s = RADIX + s
      end
      BigDecimal(s + EXP + (self.exponent + sumdiff).to_s)
    elsif self.exponent == 0 or other.exponent == 0
      if self.exponent == 0
        z = self
        nz = other
      else
        z = other
        nz = self
      end
      # so z is the one with the 0 exponent
      zd = z.digits.to_s
      nzd = nz.digits.to_s
      nzx = nz.exponent
      
      if nzx > 0
        zd = ('0' * nzx) + zd
      else # if nzx < 0
        nzd = ('0' * nzx.abs) + nzd
      end
      
      diff = zd.length - nzd.length
      if diff > 0
        nzd << '0' * diff
      else # diff < 0
        zd << '0' * diff.abs
      end
      l = zd.length
      sum = (nzd.to_i * signs[nz.sign]) + (zd.to_i * signs[z.sign])
      sumsign = sum < 0 ? MINUS : PLUS
      s = sum.abs.to_s
      sumdiff = s.length - zd.length
      BigDecimal(sumsign + RADIX + s + EXP + sumdiff.to_s)
    else
      signs = {SIGN_POSITIVE_FINITE => PLUS, SIGN_NEGATIVE_FINITE => MINUS}
      if self.exponent.abs < other.exponent.abs
        extra = self.exponent
      else
        extra = other.exponent
      end
      a = BigDecimal(signs[self.sign] + RADIX + self.digits.to_s + EXP + (self.exponent - extra).to_s)
      b = BigDecimal(signs[other.sign] + RADIX + other.digits.to_s + EXP + (other.exponent - extra).to_s)
      sum = a + b
      BigDecimal(signs[sum.sign] + RADIX + sum.digits.to_s + EXP + (sum.exponent + extra).to_s)
    end
  end

  def -(other)
    self + -other
  end

  def quo(other)
  end
  alias / quo

  def remainder(other)
  end
  alias % remainder
  
  # Unary minus
  def -@
    if self.nan?
      return self
    end
    s = self.to_s
    if @sign == MINUS
      BigDecimal(s[1..-1])
    else
      BigDecimal(MINUS + s)
    end
  end

  def >=(other)
  end

  def <=(other)
  end

  # This will need to be refactored
  def <=>(other)
    if other != 0 or self.nan?
      raise
    elsif self.finite? and @int == '0' and @frac == '0'
      return 0
    else
      case @sign
        when PLUS then return 1
        when MINUS then return -1
      end
    end
  end

  def <(other)
    return self.<=>(other) == -1
  end

  def eql?(other)
    if self.nan?
      return false
    elsif other.respond_to?(:nan?) and other.nan?
      return false
    elsif self.zero? and other.respond_to?(:zero?)
      return other.zero?
    elsif self.to_s == other.to_s
      return true
    elsif !other.kind_of?(BigDecimal)
      return self == BigDecimal(other.to_s)
    else
      return false
    end
  end
  alias == eql?

  def >(other)
    return self.<=>(other) == 1
  end
  
  ####################
  # Other operations #
  ####################
  
  # I'm trying to keep these in alphabetical order unless a good reason develops to do otherwise.
  
  def abs
    if self.nan? or @sign == PLUS
      return self
    else
      s = self.to_s.sub(/^-/, '') # strip minus sign
      BigDecimal(s)
    end
  end
  
  # Returns the exponent as a Fixnum (or 0 if out of range), such that the absolute value of the base is between 0 and 1.  This is not the power function.
  # call-seq:
  #   BigDecimal("0.125e3").exponent => 3
  #   BigDecimal("3000").exponent => 4
  #
  def exponent
    return @exp
  end
  
  def fix
    d = @digits.to_s.length
    if self.nan? or !self.finite? or d <= @exp
      return self
    elsif @exp < 0
      return BigDecimal("#{@sign}0")
    end
    s = self.to_s("F").split(RADIX)[0] # this includes the sign
    BigDecimal(s)
  end
  
  def frac
    if self.nan? or !self.finite?
      return self
    elsif @digits.to_s.length <= @exp
      return BigDecimal("0")
    end
    s = self.to_s("F").split(RADIX)[1] # the part after the decimal point
    BigDecimal(@sign + RADIX + s)
  end
  
  def sign
    if self.nan?
      SIGN_NaN
    elsif self.zero?
      @sign == PLUS ? SIGN_POSITIVE_ZERO : SIGN_NEGATIVE_ZERO
    elsif self.finite?
      @sign == PLUS ? SIGN_POSITIVE_FINITE : SIGN_NEGATIVE_FINITE
    else # infinite
      @sign == PLUS ? SIGN_POSITIVE_INFINITE : SIGN_NEGATIVE_INFINITE
    end
  end
  
  def truncate(prec = nil)
    if self.nan? or !self.finite?
      return self
    elsif prec.nil?
      self.fix
    else
      e = [0, @exp + prec].max
      s = @digits.to_s[0, e]
      BigDecimal(@sign + '0' + RADIX + s + EXP + @exp.to_s)
    end
  end
end
