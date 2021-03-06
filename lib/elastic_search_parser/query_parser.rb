module ElasticSearchParser
  class QueryParser
    extend Memoist
    include DSL::Parser
    QUERY_OPERATIONS = %i(lte lt gte gt term terms query prefix missing exists)
    attr_reader :query, :routing, :index, :body, :url
    def initialize(conditions, options = {})
      @cache               = {}
      @routings            = []
      @indexes             = []
      @options             = options.dup.with_indifferent_access
      case conditions
        when Array
          @dsl                 = conditions[0]
          @values              = conditions.from(1)
          raise ArgumentError.new(' must be a valid string!') unless self.valid_dsl?
          @question_mark_count = 0
          @query               = self.process
          @body                = {:query => {:filtered => {:filter => @query}}}
        when NilClass
        else
          raise ArgumentError.new('The input is not valid!')
      end
      @routings.include?([]) ? @routings.clear : @routings.flatten!
      @routing = @routings.uniq.join(',') if @routings.present?
      @index   = @indexes.flatten.uniq.join(',') if @indexes.present?
      @url     = Configuration.url(@indexes, @options[:elastic_search])
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
        if params[:top]
          params[:routings] << or_params[:routings]
        else
          params[:routings] += or_params[:routings]
        end
        params[:indexes].replace(params[:indexes] + or_params[:indexes])
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

      value = Utility.try_downcase(value)
      value1 = Utility.try_downcase(value1)

      # return immediately if pass an empty string, array hash inside
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

      params[:indexes]  = Configuration.query_index(sub_query, @options[:elastic_search])
      params[:routings] = Array(Configuration.query_routing(sub_query, @options[:elastic_search]))
    end

    def searchable_fields
      ret = HashWithIndifferentAccess.new
      @options[:elastic_search][:searchable_fields].each do |key, value|
        case value
          when Array, String
            ret[key] = key
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
