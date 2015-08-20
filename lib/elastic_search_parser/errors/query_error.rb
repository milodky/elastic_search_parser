module ElasticSearchParser
  class InvalidEndpoint < StandardError
    def initialize
      super('endpoint should either be a string or a hash!')
    end
  end
end