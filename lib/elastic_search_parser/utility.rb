module ElasticSearchParser
  module Utility
    def self.try_downcase(t)
      t.is_a?(Array) ? t.map{|k| try_downcase(k)} : (t.try(:downcase) || t)
    end
  end
end
