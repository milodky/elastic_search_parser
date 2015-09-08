module ElasticSearchParser
  module Configuration
    # get the type
    def self.type(params)
      params[:sharding][:type]
    end

    def self.document_id(entry_hash, params)

    end
    # this module generates the search and index params(index, routing, type etc)
    def self.query_index(conditions, params)
      index_config = params['sharding']['index']
      return index_config if index_config.is_a?(String)
      key   = index_config['key']
      range = eval(index_config['range'])
      return self.default_query_index(params) if conditions[key].blank?
      value = conditions[key]
      ret =
          if value.is_a?(Array) || value.is_a?(String)
            conditions[key]
          elsif value.is_a?(Hash)
            self.term_key(value) || self.prefix_key(value, range) || self.fuzzy_key(value, range) || self.range_key(value, range, params)
          end
      Array(ret).map do |val|
        final_key = eval(index_config['key_for_index_sharding']).cover?(val[range]) ? val[range] : index_config['default_key']
        "#{self.type(params)}#{final_key}"
      end
    rescue => err
      puts err.message
      puts err.backtrace
      raise ArgumentError.new('Failed to generate the index for query!')
    end

    def self.query_routing(conditions, params)
      return if params['mapping'].andand['_routing'].blank?
      query_key = conditions.keys[0]
      key       = params['sharding']['routing']['key']
      return if query_key != key
      range = eval(params['sharding']['routing']['range'])
      value = conditions[key]
      ret   =
          if value.is_a?(Array) || value.is_a?(String)
            conditions[key]
          elsif value.is_a?(Hash)
            self.term_key(value) || self.prefix_key(value, range) || self.fuzzy_key(value, range) || self.range_key(value, range, params, true)
          end
      Array(ret).map{|val| val[range]}.uniq
    end


    def self.term_key(value)
      value['term'] || value['terms']
    end

    def self.prefix_key(value, range)
      return if value['prefix'].nil? || value['prefix'].size < range.last
      value['prefix']
    end

    #############################################################
    # get the index/routing key for range query
    #
    def self.range_key(value, range, params, routing = false)
      return if %w(lte lt gte gt).all?{|key| value[key].blank? || (value[key].to_s.size < range.last)}
      return self.range_start_key(value, params) if self.range_start_key(value, params)[range] == self.range_end_key(value, params)[range]
      return if routing
      (self.range_start_key(value, params)[range]..self.range_end_key(value, params)[range]).to_a
    end

    def self.range_start_key(value, params)
      (value['gte'] || value['gt'] || self.default_query_index(params).first)
    end
    def self.range_end_key(value, params)
      (value['lte'] || value['lt'] || self.default_query_index(params).last)
    end
    #############################################################
    # get the index/routing key for fuzzy query
    #
    def self.fuzzy_key(value, range)
      return if params['thorough_fuzzy'] || value['fuzzy'].nil? || value['fuzzy'].size < range.last
      value['fuzzy']
    end

    def self.default_query_index(params)
      eval(params['sharding']['index']['key_for_index_sharding']).to_a.map{|k| "#{self.type(params)}#{k}"}
    end

    #############################################################
    #
    def self.transaction_index(entry_hash, params)
      index_config = params['sharding']['index']
      return index_config if index_config.is_a?(String)
      key   = index_config['key']
      range = eval(index_config['range'])
      raise ArgumentError.new('Cannot get the index for transaction!') if entry_hash[key].blank?
      final_key = eval(index_config['key_for_index_sharding']).cover?(entry_hash[key][range]) ?
          entry_hash[key][range] : index_config['default_key']
      "#{self.type(params)}#{final_key}"
    end

    def self.transaction_routing(entry_hash, params)
      return if params['mapping'].andand['_routing'].blank?
      key   = params['sharding']['routing']['key']
      range = params['sharding']['routing']['range']
      value = entry_hash[key][eval(range)]
      path  = params['mapping']['_routing']['path']
      entry_hash[path] = value
    end

    def self.url(index, params)
      case params['url']
        when String
          return params['url']
        when Hash
          if index.size > 1
            params['url']['tribe']
          else
            params['url'][index[0]]
          end
        else
          nil
      end
    rescue
      raise InvalidEndpoint
    end



  end
end
