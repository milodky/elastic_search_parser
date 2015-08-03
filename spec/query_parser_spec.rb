require 'spec_helper'
describe 'parse query conditions' do
  it 'should return the correct result when there is only one field queried are no nested fields' do
    ret = ElasticSearchParser::Read.new(['first_name = ?', 1], PERSON_MAPPING)
    expect(ret.result).to eql({:term=>{"first_name"=>1}})
  end
  it 'should return the correct result when there are two fields queried no nested fields' do
    ret = ElasticSearchParser::Read.new(['first_name = ? and last_name = ?', 1, 2], PERSON_MAPPING)
    expect(ret.result).to eql({:bool=>{:must=>[{:term=>{"first_name"=>1}}, {:term=>{"last_name"=>2}}]}})
  end

  it 'should return the correct result when there are brackets and no nested fields' do
    ret = ElasticSearchParser::Read.new(['(first_name = ? and last_name = ?)', 1, 2], PERSON_MAPPING)
    expect(ret.result).to eql({:bool=>{:must=>[{:term=>{"first_name"=>1}}, {:term=>{"last_name"=>2}}]}})
  end

  it 'should return the correct result when there are brackets around one or operation and no nested fields' do
    ret = ElasticSearchParser::Read.new(['first_name = ? and (last_name = ? or last_name = ?)', 1, 2, 3], PERSON_MAPPING)
    expect(ret.result).to eql({:bool=>{:must=>[{:term=>{"first_name"=>1}}, {:bool=>{:should=>[{:term=>{"last_name"=>2}}, {:term=>{"last_name"=>3}}]}}]}})
  end

  it 'should return the correct result when there is no bracket and one nested field' do
    ret = ElasticSearchParser::Read.new(['first_name = ? and city = ?', 1, 2], PERSON_MAPPING)
    expect(ret.result).to eql({:bool=>{:must=>[{:term=>{"first_name"=>1}}, {:nested => {:path => "location", :query => {:term=>{"location.city"=>2}}}}]}})
  end

  it 'should return the correct result when there is one nested field' do
    ret = ElasticSearchParser::Read.new(['city = ?', 1], PERSON_MAPPING)
    expect(ret.result).to eql({:nested => {:path => "location", :query => {:term=>{"location.city"=>1}}}})
  end

  it 'should return the correct result when there is no bracket and one nested field' do
    ret = ElasticSearchParser::Read.new(['first_name = ? and (city = ? or city = ?)', 1, 2, 3], PERSON_MAPPING)
    expect(ret.result).to eql({:bool=> {:must=> [
                                            {:term=>{"first_name"=>1}},
                                            {:nested => {
                                                :path => "location",
                                                :query => {
                                                    :bool => {
                                                        :should => [
                                                            {:term=>{"location.city"=>2}},
                                                            {:term=>{"location.city"=>3}}
                                                        ]
                                                    }
                                                }
                                            }}
                                        ]
                                   }})
  end

end