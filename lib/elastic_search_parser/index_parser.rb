module ElasticSearchParser
  class IndexParser
    extend Memoist
    # this class generates the convert the object hash to the correct
    # mapping format when indexing the documents
    def initialize(entry_hash, options)
      @options    = options.with_indifferent_access
      @es_options = @options[:elastic_search]
      @entry_hash = entry_hash.with_indifferent_access
      @items      = self.process
    end

    def process
      return @options[:lambda].call(@entry_hash) if @options[:lambda]
      self.final_value
    rescue => err
      raise ArgumentError.new("Error when generating the document: #{err.message}")
    end

    #############################################################
    # generate the intermediate value(shard_key, routing, index,
    # type not included)
    #
    def middle_value
      ret = HashWithIndifferentAccess.new
      @es_options[:searchable_fields].each do |field, config|
        if @es_options[:user_defined_index].andand[field]
          ret = @es_options[:user_defined_index].andand[field].call(@entry_hash)
          next
        end
        case config
          when String
            raise ArgumentError.new("#{config} is not part of the schema") if self.schema[config].nil?
            ret[field] = self.try_downcase(@entry_hash[config])
          when Array
            ret[field] = config.map do |f|
              raise ArgumentError.new("#{config} is not part of the schema") if self.schema[f].nil?
              next if @entry_hash[f].nil?
              Array(@entry_hash[f])
            end.flatten.map{|t| self.try_downcase(t)}.compact
          when Hash
            object_field = config[:path]
            raise ArgumentError.new("#{config} is not part of the schema") if self.schema[object_field].nil?
            next if @entry_hash[object_field].blank?
            type = self.schema[object_field]
            case type
              when 'Array'
                ret[field] = @entry_hash[object_field].map{|object| self.complex_object(object, config)}.reject(&:blank?)
              else
                ret[field] = self.complex_object(@entry_hash, config)
            end
        end
      end
      ret.delete_if{|_, v| v.blank?}
    end

    #############################################################
    # generate the final value(shard_key, routing, index, ype included)
    #
    def final_value
      middle_value = self.middle_value
      shard_key    = @es_options[:sharding][:index][:key]
      Array(middle_value.delete(shard_key)).map do |shard_value|
        data    = middle_value.merge(shard_key => shard_value)
        index   = Configuration.transaction_index({shard_key => shard_value}, @es_options)
        type    = Configuration.type(@es_options)
        #TODO: id haven't been added yet
        id      = Configuration.document_id(data, @es_options)
        routing = Configuration.transaction_routing(data, @es_options)
        {:data => data, :_index => index, :_type => type, :_routing => routing, :_id => id}.delete_if{|_, v| v.blank?}
      end
    end


    def complex_object(object, config)
      if config[:nested]
        # returns a hash
        {}.tap { |h| config[:fields].each { |k, v| h[k] = self.try_downcase(object[v]) if object[v].present? } }
      else
        self.try_downcase( object[config[:field]])
      end
    end

    def schema
      HashWithIndifferentAccess.new.tap do |h|
        @options[:schema].each do |field, type|
          h[field] = type.scan(/\w+/i)[0]
        end
      end
    end; memoize :schema

    def try_downcase(t)
      t.try(:downcase) || t
    end

  end
end