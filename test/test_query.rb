require 'helper'

class TestQuery < AVTestCase

  EMPTY_QUERY_RESPONSE = {AV::Protocol::KEY_RESULTS => []}

  def test_get
    VCR.use_cassette('test_get', :record => :new_episodes) do
      post = AV::Object.new "Post"
      post["title"] = "foo"
      post.save

      q = AV.get("Post", post.id)

      assert_equal q.id, post.id
      assert_equal q["title"], post["title"]
    end
  end

  def test_add_contraint
    # I know this method *should* be private.
    # But then it would be a PITA to test.
    # I'd rather test this one method than pointlessly test many others.
    # Thus is life.

    q = AV::Query.new "TestQuery"
    q.add_constraint("points", 5)
    assert_equal q.where["points"], 5
    q.add_constraint("player", { "$regex" => "regex voodoo"})
    assert_equal q.where["player"], { "$regex" => "regex voodoo"}
  end

  def test_related_to
    q = AV::Query.new "Comment"
    pointer = AV::Pointer.new(class_name: "Post", parse_object_id: '1234')
    q.related_to("comments", pointer)

    assert_not_nil q.where["$relatedTo"]
    assert_equal pointer, q.where["$relatedTo"]["object"]
    assert_equal q.where["$relatedTo"]["key"], "comments"
  end

  def test_eq
    q = AV::Query.new "TestQuery"
    q.eq("points", 5)
    assert_equal q.where, {"points" => 5}
    q.eq("player", "michael@jordan.com")
    assert_equal q.where, {"points" =>  5, "player" => "michael@jordan.com"}
  end

  def test_eq_pointerize
    VCR.use_cassette('test_eq_pointerize', :record => :new_episodes) do
      foo = AV::Object.new("Foo")
      foo.save
      bar = AV::Object.new("Bar", "foo" => foo.pointer, "bar" => "bar")
      bar.save

      assert_equal "bar", AV::Query.new("Bar").eq("foo", foo.pointer).get.first["bar"]
      assert_equal "bar", AV::Query.new("Bar").eq("foo", foo).get.first["bar"]
    end
  end

  def test_limit_skip
    VCR.use_cassette('test_limit_skip', :record => :new_episodes) do
      q = AV::Query.new "TestQuery"
      q.limit = 2
      q.skip = 3
      query_matcher = has_entries(:limit =>  2, :skip => 3)
      AV::Client.any_instance.expects(:request).with(anything, :get, nil, query_matcher).returns(EMPTY_QUERY_RESPONSE)
      q.get
    end
  end

  def test_count
    VCR.use_cassette('test_count', :record => :new_episodes) do
      q = AV::Query.new "TestQuery"
      q.count = true
      query_matcher = has_entries(:count => true)
      AV::Client.any_instance.expects(:request).with(anything, :get, nil, query_matcher).returns(EMPTY_QUERY_RESPONSE.merge("count" => 1000))
      results = q.get
      assert_equal 1000, results['count']
    end
  end

  def test_include
    VCR.use_cassette('test_include', :record => :new_episodes) do
      post_1 = AV::Object.new "Post"
      post_1['title'] = 'foo'
      post_1.save

      post_2 = AV::Object.new "Post"
      post_2['title'] = 'bar'
      post_2['other'] = post_1.pointer
      post_2.save

      q = AV::Query.new "Post"
      q.eq('objectId', post_2.parse_object_id)
      q.include = 'other'

      assert_equal 'foo', q.get.first['other']['title']
    end
  end

  def test_or
    #VCR.use_cassette('test_or', :record => :new_episodes) do
      foo = AV::Object.new "Post"
      foo["random"] = rand
      foo.save
      foo_query = AV::Query.new("Post").eq("random", foo["random"])
      assert_equal 1, foo_query.get.size

      bar = AV::Object.new "Post"
      bar["random"] = rand
      bar.save
      bar_query = AV::Query.new("Post").eq("random", bar["random"])
      assert_equal 1, foo_query.get.size

      query = foo_query.or(bar_query)
      assert_equal 2, query.get.size
    #end
  end

  def test_in_query
    outer_query = AV::Query.new "Outer"
    inner_query = AV::Query.new "Inner"
    inner_query.eq("foo", "bar")
    outer_query.in_query("inner", inner_query)
    assert_equal({"inner"=>{"$inQuery"=>{"className"=>"Inner", "where"=>{"foo"=>"bar"}}}}, outer_query.where)
  end

  def test_large_value_in_xget
    VCR.use_cassette('test_xget', :record => :new_episodes) do
      post = AV::Object.new("Post")
      post['title']= 'foo'
      post.save

      other_post = AV::Object.new("Post")
      other_post['title']= 'foo'
      other_post.save

      assert_equal [post], AV::Query.new("Post").value_in("objectId", [post.id] + 100.times.map { "x" }).get
    end
  end

  def test_bad_response
    VCR.use_cassette('test_bad_response', :record => :new_episodes) do
      AV::Client.any_instance.expects(:request).returns("crap")
      assert_raises do
        AV::Query.new("Post").get
      end
    end
  end

  def test_contains_all
    VCR.use_cassette('test_contains_all', :record => :new_episodes) do

      #ensure cacti from the previous test to not hang around
      q = AV::Query.new "Cactus"
      cacti = q.get
      cacti.each do |cactus|
        cactus.parse_delete
      end
      #end ensure

      cactus = AV::Object.new "Cactus"
      cactus['array'] = [1, 2, 5, 6, 7]
      cactus.save

      second_cactus = AV::Object.new "Cactus"
      second_cactus['array'] = [3, 4, 5, 6]
      second_cactus.save

      contains_query = AV::Query.new("Cactus").contains_all('array', [5, 6])
      assert_equal 2, contains_query.get.size

      with_one_query = AV::Query.new("Cactus").contains_all('array', [1,5,6])
      assert_equal 1, with_one_query.get.size
      assert_equal [cactus], with_one_query.get

      with_four_query = AV::Query.new("Cactus").contains_all('array', [4,5,6])
      assert_equal 1, with_four_query.get.size
      assert_equal [second_cactus], with_four_query.get

      with_nine_query = AV::Query.new("Cactus").contains_all('array', [9])
      assert_equal 0, with_nine_query.get.size
    end
  end
end
