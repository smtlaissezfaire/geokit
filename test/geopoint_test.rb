require 'test/unit'
require File.expand_path(File.join(File.dirname(__FILE__), '../../../../config/environment.rb'))

class GeoPointTest < Test::Unit::TestCase #:nodoc: all
  
  def setup
    @loc_a = GeoKit::GeoPoint.new(32.918593,-96.958444)
    @loc_e = GeoKit::GeoPoint.new(32.969527,-96.990159)
    @point = GeoKit::GeoPoint.new(@loc_a.lat, @loc_a.lng)
  end
  
  def test_distance_between_same_using_defaults
    assert_equal 0, GeoKit::GeoPoint.distance_between(@loc_a, @loc_a)
    assert_equal 0, @loc_a.distance_to(@loc_a)
  end
  
  def test_distance_between_same_with_miles_and_flat
    assert_equal 0, GeoKit::GeoPoint.distance_between(@loc_a, @loc_a, :units => :miles, :formula => :flat)
    assert_equal 0, @loc_a.distance_to(@loc_a, :units => :miles, :formula => :flat)
  end

  def test_distance_between_same_with_kms_and_flat
    assert_equal 0, GeoKit::GeoPoint.distance_between(@loc_a, @loc_a, :units => :kms, :formula => :flat)
    assert_equal 0, @loc_a.distance_to(@loc_a, :units => :kms, :formula => :flat)
  end
  
  def test_distance_between_same_with_miles_and_sphere
    assert_equal 0, GeoKit::GeoPoint.distance_between(@loc_a, @loc_a, :units => :miles, :formula => :sphere)
    assert_equal 0, @loc_a.distance_to(@loc_a, :units => :miles, :formula => :sphere)
  end
  
  def test_distance_between_same_with_kms_and_sphere
    assert_equal 0, GeoKit::GeoPoint.distance_between(@loc_a, @loc_a, :units => :kms, :formula => :sphere)
    assert_equal 0, @loc_a.distance_to(@loc_a, :units => :kms, :formula => :sphere)
  end
  
  def test_distance_between_diff_using_defaults
    assert_in_delta 3.97, GeoKit::GeoPoint.distance_between(@loc_a, @loc_e), 0.01
    assert_in_delta 3.97, @loc_a.distance_to(@loc_e), 0.01
  end
  
  def test_distance_between_diff_with_miles_and_flat
    assert_in_delta 3.97, GeoKit::GeoPoint.distance_between(@loc_a, @loc_e, :units => :miles, :formula => :flat), 0.2
    assert_in_delta 3.97, @loc_a.distance_to(@loc_e, :units => :miles, :formula => :flat), 0.2
  end

  def test_distance_between_diff_with_kms_and_flat
    assert_in_delta 6.39, GeoKit::GeoPoint.distance_between(@loc_a, @loc_e, :units => :kms, :formula => :flat), 0.4
    assert_in_delta 6.39, @loc_a.distance_to(@loc_e, :units => :kms, :formula => :flat), 0.4
  end
  
  def test_distance_between_diff_with_miles_and_sphere
    assert_in_delta 3.97, GeoKit::GeoPoint.distance_between(@loc_a, @loc_e, :units => :miles, :formula => :sphere), 0.01
    assert_in_delta 3.97, @loc_a.distance_to(@loc_e, :units => :miles, :formula => :sphere), 0.01
  end
  
  def test_distance_between_diff_with_kms_and_sphere
    assert_in_delta 6.39, GeoKit::GeoPoint.distance_between(@loc_a, @loc_e, :units => :kms, :formula => :sphere), 0.01
    assert_in_delta 6.39, @loc_a.distance_to(@loc_e, :units => :kms, :formula => :sphere), 0.01
  end
  
  def test_manually_mixed_in
    assert_equal 0, GeoKit::GeoPoint.distance_between(@point, @point)
    assert_equal 0, @point.distance_to(@point)
    assert_equal 0, @point.distance_to(@loc_a)
    assert_in_delta 3.97, @point.distance_to(@loc_e, :units => :miles, :formula => :flat), 0.2
    assert_in_delta 6.39, @point.distance_to(@loc_e, :units => :kms, :formula => :flat), 0.4
  end
  
end