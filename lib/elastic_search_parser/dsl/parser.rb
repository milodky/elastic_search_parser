module ElasticSearchParser
  module DSL
    module Parser
    # return is an array
    def parse_dsl(dsl)
      while dsl[0] == '(' && dsl[-1] == ')'
        dsl = dsl[1...-1]
      end
      return dsl if dsl.count('(') == 0
      @cache           = {}
      last_right_index = -1
      ret = []
      i   = 0

      begin
        # next if it's not a bracket
        next if dsl[i] != '(' && (i += 1)
        # find the corresponding right bracket
        right_bracket_index = corresponding_right_bracket(dsl, i)
        replacing_string    = self.random_string
        internal_dsl        = self.parse_dsl(dsl[(i + 1)...right_bracket_index])
        ret << dsl[(last_right_index + 1)...i]
        ret << replacing_string
        i = right_bracket_index + 1
        @cache[replacing_string] = internal_dsl
        last_right_index = right_bracket_index
      end while i < dsl.size
      ret << dsl[(last_right_index + 1)..i]
      ret.reject(&:blank?).join(' ')
    end
    def valid_dsl?
      return unless @dsl.is_a?(String) || @dsl.empty?
      left_bracket_count = 0
      @dsl.each_char do |c|
        case c
          when '(' then left_bracket_count += 1
          when ')' then left_bracket_count -= 1
        end
        return if left_bracket_count < 0
      end
      true
    end

    def corresponding_right_bracket(dsl, left_index)
      left_bracket_count = 1
      (left_index + 1).upto(dsl.size - 1) do |index|
        case dsl[index]
          when '(' then left_bracket_count += 1
          when ')' then left_bracket_count -= 1
        end
        return index if left_bracket_count == 0
      end
    end

    def random_string
      (0..10).map{('a'..'z').to_a.sample}.join
    end
    end

  end
end