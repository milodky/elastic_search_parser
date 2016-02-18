require 'spec_helper'
describe 'generate document for indexing' do
  before(:all) do
    @p_hash = valid_person_mapping
    @ret    = ElasticSearchParser::IndexParser.new(@p_hash, PERSON_MAPPING)
    @items  = @ret.items
  end
  it 'should generate two items' do
    expect(@items).to be_kind_of(Array)
    expect(@items.size).to eql(@p_hash[:last_names].size)
  end

  it 'should generate the correct elastic search document id' do
    last_names = @p_hash[:last_names]
    @items.each_with_index do |item, i|
      _id = item[:_id]
      expect(_id).to eql([@p_hash[:id], last_names[i].downcase].join('_'))
    end
  end

  it 'should have correct routing value' do
    last_names = @p_hash[:last_names]
    @items.each_with_index do |item, i|
      expect(item[:_routing]).to eql(last_names[i][0, 3].downcase)
    end
  end

  it 'should have correct index value' do
    last_names = @p_hash[:last_names]
    @items.each_with_index do |item, i|
      expect(item[:_index]).to eql("c#{last_names[i][0, 1].downcase}")
    end
  end

  it 'should have correct type value' do
    @items.each_with_index do |item|
      expect(item[:_type]).to eql('c')
    end
  end

  it 'should have correct last_name' do
    last_names = @p_hash[:last_names]
    @items.each_with_index do |item, i|
      expect(item[:data][:last_name]).to eql(last_names[i].downcase)
    end
  end

  it 'should have correct shard_key value' do
    last_names = @p_hash[:last_names]
    @items.each_with_index do |item, i|
      expect(item[:data][:shard_key]).to eql(last_names[i][0, 3].downcase)
    end
  end

  it 'should have correct first_names' do
    first_names = @p_hash[:first_names]
    @items.each do |item|
      expect(item[:data][:first_name]).to eql(first_names.map(&:downcase))
    end
  end

  it 'should have correct locations' do
    locations = @p_hash[:locations]
    @items.each do |item|
      expect(item[:data][:location]).to be_kind_of(Array)
      expect(item[:data][:location]).to be_present

      item[:data][:location].each_with_index do |location, i|
        expect(location[:city]).to eql(locations[i][:city].downcase)
        expect(location[:state]).to eql(locations[i][:state])
      end

    end
  end
end