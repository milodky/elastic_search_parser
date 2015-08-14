require 'spec_helper'
describe 'generate document for indexing' do
  it 'should generate the correct elastic search document' do
    p_hash = valid_person_mapping
    ret    = ElasticSearchParser::IndexParser.new(p_hash, PERSON_MAPPING)
  end

  # here I also need to test the routing and shard_key stuff

end