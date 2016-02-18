require 'spec_helper'
describe 'parse query conditions' do
  it 'should return the correct result when there is only one field queried are no nested fields' do
    ret = ElasticSearchParser::QueryParser.new(['first_name = ?', 1], PERSON_MAPPING)
    expect(ret.query).to eql({:term=>{'first_name'=>1}})
    expect(ret.routing).to be_nil
    expect(ret.index).to eql('ca,cb,cc,cd,ce,cf,cg,ch,ci,cj,ck,cl,cm,cn,co,cp,cq,cr,cs,ct,cu,cv,cw,cx,cy,cz')
  end
  it 'should return the correct result when there are two fields queried no nested fields' do
    ret = ElasticSearchParser::QueryParser.new(['first_name = ? and last_name = ?', 'david', 'williams'], PERSON_MAPPING)
    expect(ret.routing).to eql('wil')
    expect(ret.index).to eql('cw')
    expect(ret.query).to eql({:bool=>{:must=>[{:term=>{'first_name'=>'david'}}, {:term=>{'last_name'=>'williams'}}]}})
  end

  it 'should return the correct result when there are brackets and no nested fields' do
    ret = ElasticSearchParser::QueryParser.new(['(first_name = ? and last_name = ?)', 1, 'williams'], PERSON_MAPPING)
    expect(ret.query).to eql({:bool=>{:must=>[{:term=>{'first_name'=>1}}, {:term=>{'last_name'=>'williams'}}]}})
    expect(ret.routing).to eql('wil')
    expect(ret.index).to eql('cw')
  end

  it 'should return the correct result when there are brackets around one or operation and no nested fields' do
    ret = ElasticSearchParser::QueryParser.new(['first_name = ? and (last_name = ? or last_name = ?)', 1, 'smith', 'williams'], PERSON_MAPPING)
    expect(ret.query).to eql({:bool=>{:must=>[{:term=>{'first_name'=>1}}, {:bool=>{:should=>[{:term=>{'last_name'=>  'smith'}}, {:term=>{'last_name'=> 'williams'}}]}}]}})
    expect(ret.routing).to eql('smi,wil')
    expect(ret.index).to eql('cs,cw')
  end

  it 'should return the correct result when there are brackets around one or operation and no nested fields' do
    ret = ElasticSearchParser::QueryParser.new(['first_name = ? and (last_name = ? or last_name = ?)', ['Joshua', 'JOHN'], 'Smith', 'Williams'], PERSON_MAPPING)
    expect(ret.query).to eql({:bool=>{:must=>[{:terms=>{'first_name'=>['joshua', 'john']}}, {:bool=>{:should=>[{:term=>{'last_name'=>  'smith'}}, {:term=>{'last_name'=> 'williams'}}]}}]}})
    expect(ret.routing).to eql('smi,wil')
    expect(ret.index).to eql('cs,cw')
  end

  it 'should return the correct result when there is no bracket and one nested field' do
    ret = ElasticSearchParser::QueryParser.new(['first_name = ? and city = ?', 1, 2], PERSON_MAPPING)
    expect(ret.query).to eql({:bool=>{:must=>[{:term=>{'first_name'=>1}}, {:nested => {:path => 'location', :query => {:term=>{'location.city'=>2}}}}]}})
    expect(ret.routing).to be_nil
    expect(ret.index).to eql('ca,cb,cc,cd,ce,cf,cg,ch,ci,cj,ck,cl,cm,cn,co,cp,cq,cr,cs,ct,cu,cv,cw,cx,cy,cz')
  end

  it 'should return the correct result when there is one nested field' do
    ret = ElasticSearchParser::QueryParser.new(['city = ?', 1], PERSON_MAPPING)
    expect(ret.query).to eql({:nested => {:path => 'location', :query => {:term=>{'location.city'=>1}}}})
    expect(ret.routing).to be_nil
    expect(ret.index).to eql('ca,cb,cc,cd,ce,cf,cg,ch,ci,cj,ck,cl,cm,cn,co,cp,cq,cr,cs,ct,cu,cv,cw,cx,cy,cz')
  end

  it 'should return the correct result when there is one nested field' do
    ret = ElasticSearchParser::QueryParser.new(['(last_name = ? and first_name = ?) or first_name = ?', 'smith', 'john', 'david'], PERSON_MAPPING)
    expect(ret.query).to eql({:bool=>{:should=>[ {:bool => {:must => [{:term=>{'last_name'=>'smith'}}, {:term=>{'first_name'=> 'john'}}]}}, {:term => {'first_name' => 'david'}}]}})
    expect(ret.routing).to be_nil
    expect(ret.index.split(',').sort.join(',')).to eql('ca,cb,cc,cd,ce,cf,cg,ch,ci,cj,ck,cl,cm,cn,co,cp,cq,cr,cs,ct,cu,cv,cw,cx,cy,cz')

  end

  it 'should return the correct result when there is no bracket and one nested field' do
    ret = ElasticSearchParser::QueryParser.new(['first_name = ? and (city = ? or city = ?)', 1, 2, 3], PERSON_MAPPING)
    expect(ret.query).to eql({:bool=> {:must=> [
                                            {:term=>{'first_name'=>1}},
                                            {:nested => {
                                                :path => 'location',
                                                :query => {
                                                    :bool => {
                                                        :should => [
                                                            {:term=>{'location.city'=>2}},
                                                            {:term=>{'location.city'=>3}}
                                                        ]
                                                    }
                                                }
                                            }}
                                        ]
                                   }})
    expect(ret.routing).to be_nil
    expect(ret.index).to eql('ca,cb,cc,cd,ce,cf,cg,ch,ci,cj,ck,cl,cm,cn,co,cp,cq,cr,cs,ct,cu,cv,cw,cx,cy,cz')
  end

end