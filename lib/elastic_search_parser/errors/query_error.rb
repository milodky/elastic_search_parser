module ElasticSearchParser
  class InvalidEndpoint < StandardError
    def initialize
      super('url should either be a string or a hash!')
    end
  end
end