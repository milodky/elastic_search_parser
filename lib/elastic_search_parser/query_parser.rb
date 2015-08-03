module ElasticSearchParser
  class QueryParser
    extend Memoist
    QUERY_OPERATIONS = %i(lte lt gte gt term terms query prefix missing exists)
    attr_reader :result
    def initialize(conditions, options = {})
      raise ArgumentError.new('Input must be an array!') unless conditions.is_a?(Array)
      @dsl = conditions[0]
      raise ArgumentError.new(' must be a valid string!') unless self.valid_dsl?
      @values              = conditions.from(1)
      @cache               = {}
      # TODO: need to add the routings
      @routings            = []
      @question_mark_count = 0
      @options             = options.with_indifferent_access
      @result              = process
    end
    def process
      return {} if (dsl = self.parse_dsl(@dsl)).blank?
      self.parse_or(dsl)
    end
  
    def parse_or(dsl, top = true)
      should = dsl.split(/ or /i).map { |or_clause| self.parse_and(or_clause, top) }.reject(&:blank?)
      should.size == 1 ? should[0] : {:bool => {:should => should}}
    end
  
    def parse_and(or_clause, top)
      must = or_clause.split(/ and /i).map(&:strip).map do |and_clause|
        @cache[and_clause] ? self.parse_or(@cache[and_clause], false) : self.translate(and_clause)
      end
      # add the nested query here
      if top
        must += self.nested_fields.map do |nested_field|
          nested = self.nest_query_objects(nested_field, must)
          next if nested.blank?
          nested = nested.is_a?(Array) && nested.size == 1 ? nested[0] : {:bool => {:must => nested}}
          {:nested => {:path => nested_field, :query => nested}}
        end.compact
      end

      must = must.uniq.reject(&:blank?)

      must.size == 1 ? must[0] : {:bool => {:must => must}}
    end

    def nest_query_objects(field, query)
      case query
        when Array
          ret = query.map{|sub_query| self.nest_query_objects(field, sub_query)}.reject(&:blank?)
          query.delete_if(&:blank?)
        when Hash
          ret = {}
          query.each do |key, value|
            sub_query = self.nest_query_objects(field, value)
            if QUERY_OPERATIONS.include?(key)
              search_field = sub_query.to_a[0][0]
              if search_field =~ /#{field}/
                ret[key] = value
                query.delete(key)
              end
            else
              ret[key] = sub_query if sub_query.present?
            end
          end
          query.delete_if{|_, v| v.blank?}
        else
          ret = query
      end
      ret
    end
  
    def translate(and_clause)
      key, value = and_clause.squeeze(' ').split(/>=|<=|=|<|>| between | in | begins_with | like | is /i).map(&:strip)
      key        = self.searchable_fields[key]
      value1     = nil
      if value =~ / between /i
        if value =~ /\? between \?/i
          value = @values[@question_mark_count]
          @question_mark_count += 1 
          value1 = @values[@question_mark_count]
          @question_mark_count += 1 
        elsif value =~ /\? between /i
          _, value1 = value.split(/between /i)
          value = @values[@question_mark_count]
          @question_mark_count += 1 
        elsif value =~ / between \?/i
          _, value = value.split(/ between/i)[0].split(' ')
          value1   = @values[@question_mark_count]
          @question_mark_count += 1 
        else
          value, value1 = value.split(/ between /i)
          _, value = value.split(' ')
        end
         
      elsif value.include?('?')
        value = @values[@question_mark_count]
        @question_mark_count += 1 
      end
      self.add_routing(key, value, value1)

      case and_clause
        when />=/             then {:range => {key => {:gte => value}}}
        when /<=/             then {:range => {key => {:lte => value}}}
        when /</              then {:range => {key => {:lt  => value}}}
        when />/              then {:range => {key => {:gt  => value}}}
        when / between /i     then {:range => {key => {:gte => value, :lte => value1}}}
        when / begins_with /i then {:prefix => {key => value}}
        when / like /i        then {:query => {:fuzzy => {key => value}}}
        when /=| in | is /
          value = value[0] if value.is_a?(Array) && value.size == 1
          if value.is_a?(Array)
            {:terms => {key => value}}
          elsif value =~ /^null$/i
            {:missing => {:field => value}}
          elsif value =~ /^not null$/i
            {:exists  => {:field => value}}
          else
            {:term => {key => value}}
          end
        else
          raise ArgumentError.new('Undefined operation!')
      end

    rescue => err
      puts err.message
      puts err.backtrace
      raise ArgumentError.new('Cannot parse the input!')
    end
  
    def add_routing(key, value, value1)
    end
  
    # return is an array
    def parse_dsl(dsl)
      while dsl[0] == '(' && dsl[-1] == ')'
        dsl = dsl[1...-1] 
      end
      return dsl if dsl.count('(') == 0
  
      last_right_index = -1
      ret = []
      i   = 0
      begin
        if dsl[i] != '('
          i += 1
          next
        end
        # find the corresponding right bracket
        right_bracket_index = corresponding_right_bracket_index(dsl, i)
        replacing_string   = self.random_string
        internal_dsl       = self.parse_dsl(dsl[(i + 1)...right_bracket_index])
        ret << dsl[(last_right_index + 1)...i]
        ret << replacing_string
        i = right_bracket_index + 1
        @cache[replacing_string] = internal_dsl
      end while i < dsl.size
      ret.join(' ')
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
  
    def corresponding_right_bracket_index(dsl, left_index)
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

    def searchable_fields
      ret = HashWithIndifferentAccess.new
      @options[:searchable_fields].each do |key, value|
        case value
          when Array, String
            ret[key] = value
          when Hash
            # everything that contains a dot will be regarded as a nested field
            value[:fields].each_key do |nested_key|
              ret[nested_key]             = "#{key}.#{nested_key}"
              ret["#{key}.#{nested_key}"] = "#{key}.#{nested_key}"
            end
          else
            raise ArgumentError
        end
      end
      ret
    rescue => err
      puts err.message
      puts err.backtrace
      raise ArgumentError.new('Failed to parse the searchable_fields!')
    end; memoize :searchable_fields
    def nested_fields
      @options[:searchable_fields].map do |key, value|
        key if value.is_a?(Hash)
      end.compact
    end; memoize :nested_fields
  end
end
