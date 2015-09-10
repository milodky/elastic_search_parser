module ElasticSearchParser
  class QueryParser
    extend Memoist
    QUERY_OPERATIONS = %i(lte lt gte gt term terms query prefix missing exists)
    attr_reader :query, :routing, :index, :body, :url
    def initialize(conditions, options = {})
      raise ArgumentError.new('Input must be an array!') unless conditions.is_a?(Array)
      @dsl = conditions[0]
      raise ArgumentError.new(' must be a valid string!') unless self.valid_dsl?
      @values              = conditions.from(1)
      @cache               = {}
      # TODO: need to add the routings
      @routings            = []
      @indexes             = []
      @question_mark_count = 0
      @options             = options.dup.with_indifferent_access
      @query               = self.process
      @routings.clear if @routings.include?(nil)
      @routing             = @routings.uniq.join(',') if @routings.present?

      @index               = @indexes.uniq.join(',')
      @body                = {:query => {:filtered => {:filter => @query}}}
      @url = Configuration.url(@indexes, @options[:elastic_search])
    end
    def process
      return {} if (dsl = self.parse_dsl(@dsl)).blank?
      params = {:indexes => @indexes, :routings => @routings, :top => true}
      self.parse_or(dsl, params)
    end
  
    def parse_or(dsl, params)
      should = dsl.split(/ or /i).map do |or_clause|
        or_params = {:routings => [], :indexes => [], :top => params[:top]}
        ret = self.parse_and(or_clause, or_params)
        [:routings, :indexes].each { |key| params[key].replace(params[key] + or_params[key]) }
        ret
      end.reject(&:blank?)
      # TODO: check the size == 0
      should.size == 1 ? should[0] : {:bool => {:should => should}}
    end
  
    def parse_and(or_clause, params)
      must = or_clause.split(/ and /i).map(&:strip).map do |and_clause|
        and_params = {:routings => [], :indexes => []}
        ret = @cache[and_clause] ?
            self.parse_or(@cache[and_clause], and_params) : self.translate(and_clause, and_params)
        [:routings, :indexes].each do |key|
          next if and_params[key].blank?
          if params[key].blank?
            params[key].replace(params[key] + and_params[key])
          else
            params[key].replace(params[key] & and_params[key])
          end
        end
        return if ret.blank?
        ret
      end

      # add routing and index here


      # add the nested query here
      if params[:top]
        must += self.nested_fields.map do |nested_field|
          nested = self.nest_query_objects(nested_field, must)
          next if nested.blank?
          nested = nested.is_a?(Array) && nested.size == 1 ? nested[0] : {:bool => {:must => nested}}
          {:nested => {:path => nested_field, :query => nested}}
        end.compact
      end

      must = must.uniq.reject(&:blank?)
      # TODO: check the size == 0
      must.size == 1 ? must[0] : {:bool => {:must => must}}
    end

    #
    # TODO: still can be optimized
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
  
    def translate(and_clause, params)
      key, value = and_clause.squeeze(' ').split(/>=|<=|=|<|>| between | in | begins_with | like | is /i).map(&:strip)
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
      return if value.blank?

      key = self.searchable_fields[key]
      ret =
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
      self.update_query_params(ret, params)
      ret
    rescue => err
      puts err.message
      puts err.backtrace
      raise ArgumentError.new('Cannot parse the input!')
    end
  
    def update_query_params(query, params)
      sub_query =
          case
            when query[:range] then query[:range]
            when query[:prefix] || query[:terms] || query[:term] || query[:query]
              operator, data = (query || query[:query]).to_a[0]
              key, value = data.to_a[0]

              {key => {operator => value}}.with_indifferent_access
            else nil
          end
      return if sub_query.blank?

      routings           = Configuration.query_routing(sub_query, @options[:elastic_search])
      params[:indexes]   = Configuration.query_index(sub_query, @options[:elastic_search])

      return if routings.nil?
      params[:routings] += routings.blank? ? [nil] : routings
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
        # next if it's not a bracket
        next if dsl[i] != '(' && (i += 1)
        # find the corresponding right bracket
        right_bracket_index = corresponding_right_bracket_index(dsl, i)
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
      @options[:elastic_search][:searchable_fields].each do |key, value|
        case value
          when Array, String
            ret[key] = value
          when Hash
            # everything that contains a dot will be regarded as a nested field
            # TODO: need to update the code here
            if value[:nested]
              value[:fields].each_key do |nested_key|
                ret[nested_key]             = "#{key}.#{nested_key}"
                ret["#{key}.#{nested_key}"] = "#{key}.#{nested_key}"
              end
            else
              ret[key] = value[:field]
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
      @options[:elastic_search][:searchable_fields].map do |key, value|
        key if value.is_a?(Hash) && value[:nested]
      end.compact
    end; memoize :nested_fields
  end
end
