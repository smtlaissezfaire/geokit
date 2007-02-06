require File.dirname(__FILE__) + '/base_geocoder_test.rb'

GeoKit::Geocoders::PROVIDER_ORDER=[:google,:yahoo,:us]

class MultiGeocoderTest < BaseGeocoderTest #:nodoc: all
  
  def setup
    super
    @failure = GeoKit::GeoLoc.new
  end
  
  def test_successful_first
    GeoKit::Geocoders::GoogleGeocoder.expects(:geocode).with(@address).returns(@success)
    assert_equal @success, GeoKit::Geocoders::MultiGeocoder.geocode(@address)
  end
  
  def test_failover
    GeoKit::Geocoders::GoogleGeocoder.expects(:geocode).with(@address).returns(@failure)
    GeoKit::Geocoders::YahooGeocoder.expects(:geocode).with(@address).returns(@success)
    assert_equal @success, GeoKit::Geocoders::MultiGeocoder.geocode(@address)    
  end
  
  def test_double_failover
    GeoKit::Geocoders::GoogleGeocoder.expects(:geocode).with(@address).returns(@failure)
    GeoKit::Geocoders::YahooGeocoder.expects(:geocode).with(@address).returns(@failure)
    GeoKit::Geocoders::UsGeocoder.expects(:geocode).with(@address).returns(@success)
    assert_equal @success, GeoKit::Geocoders::MultiGeocoder.geocode(@address)    
  end
  
  def test_failure
    GeoKit::Geocoders::GoogleGeocoder.expects(:geocode).with(@address).returns(@failure)
    GeoKit::Geocoders::YahooGeocoder.expects(:geocode).with(@address).returns(@failure)
    GeoKit::Geocoders::UsGeocoder.expects(:geocode).with(@address).returns(@failure)
    assert_equal @failure, GeoKit::Geocoders::MultiGeocoder.geocode(@address)    
  end
end