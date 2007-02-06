$:.unshift(File.dirname(__FILE__) + '/../lib')
require 'test/unit'
require 'net/http'
require 'rubygems'
require 'mocha'
require File.expand_path(File.join(File.dirname(__FILE__), '../../../../config/environment.rb'))

class MockSuccess < Net::HTTPSuccess #:nodoc: all
  def initialize
  end
end

class MockFailure < Net::HTTPServiceUnavailable #:nodoc: all
  def initialize
  end
end

# Base class for testing geocoders.
class BaseGeocoderTest < Test::Unit::TestCase #:nodoc: all
  # Defines common test fixtures.
  def setup
    @address = 'San Francisco, CA'    
    @full_address = '100 Spear St, San Francisco, CA, 94105-1522, US'   
    @full_address_short_zip = '100 Spear St, San Francisco, CA, 94105, US' 
    
    @success = GeoKit::GeoLoc.new({:city=>"SAN FRANCISCO", :state=>"CA", :country_code=>"US", :lat=>37.7742, :lng=>-122.417068})
    @success.success = true    
  end  
  
  def test_find_geocoder_methods
    public_methods = GeoKit::Geocoders::Geocoder.public_methods
    assert public_methods.include?("yahoo_geocoder")
    assert public_methods.include?("google_geocoder")
    assert public_methods.include?("ca_geocoder")
    assert public_methods.include?("us_geocoder")
    assert public_methods.include?("multi_geocoder")
    assert public_methods.include?("ip_geocoder")
  end
end