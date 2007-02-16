$:.unshift(File.dirname(__FILE__) + '/../lib')
require 'test/unit'
require File.expand_path(File.join(File.dirname(__FILE__), '../../../../config/environment.rb'))
require 'breakpoint'
require 'active_record/fixtures'
require 'action_controller/test_process'
require 'rubygems'
require 'mocha'

# Config database connection.
config = YAML::load(IO.read(File.dirname(__FILE__) + '/database.yml'))
ActiveRecord::Base.logger = Logger.new(File.dirname(__FILE__) + "/debug.log")
ActiveRecord::Base.establish_connection(config[ENV['DB'] || 'mysql'])
#ActiveRecord::Base.establish_connection(config[ENV['DB'] || 'postgresql'])


# Establish test tables.
load(File.dirname(__FILE__) + "/schema.rb")

GeoKit::Geocoders::PROVIDER_ORDER=[:google,:us]

# Uses defaults
class Company < ActiveRecord::Base #:nodoc: all
  has_many :locations
end

# Configures everything.
class Location < ActiveRecord::Base #:nodoc: all
  belongs_to :company
  acts_as_mappable
end

class CustomLocation < ActiveRecord::Base #:nodoc: all
  belongs_to :company
  acts_as_mappable :distance_column_name => 'dist', 
                   :default_units => :kms, 
                   :default_formula => :flat, 
                   :lat_column_name => 'latitude', 
                   :lng_column_name => 'longitude'
                   
  def to_s
    "lat: #{latitude} lng: #{longitude} dist: #{dist}"
  end
end

class ActsAsMappableTest < Test::Unit::TestCase #:nodoc: all
    
  LOCATION_A_IP = "217.10.83.5"  
    
  self.fixture_path = File.dirname(__FILE__) + '/fixtures'  
  fixtures :companies, :locations, :custom_locations

  def setup
    @location_a = GeoKit::GeoLoc.new
    @location_a.lat = 32.918593
    @location_a.lng = -96.958444
    @location_a.city = "Irving"
    @location_a.state = "TX"
    @location_a.country_code = "US"
    @location_a.success = true
    
    @starbucks = companies(:starbucks)
    @loc_a = locations(:a)
    @custom_loc_a = custom_locations(:a)
    @loc_e = locations(:e)
    @custom_loc_e = custom_locations(:e)    
  end
  
  def test_distance_between_geocoded
    GeoKit::Geocoders::MultiGeocoder.expects(:geocode).with("Irving, TX").returns(@location_a)
    GeoKit::Geocoders::MultiGeocoder.expects(:geocode).with("San Francisco, CA").returns(@location_a)
    assert_equal 0, Location.distance_between("Irving, TX", "San Francisco, CA") 
  end
  
  def test_distance_to_geocoded
    GeoKit::Geocoders::MultiGeocoder.expects(:geocode).with("Irving, TX").returns(@location_a)
    assert_equal 0, @custom_loc_a.distance_to("Irving, TX") 
  end
  
  def test_distance_to_geocoded_error
    GeoKit::Geocoders::MultiGeocoder.expects(:geocode).with("Irving, TX").returns(GeoKit::GeoLoc.new)
    assert_raise(GeoKit::Geocoders::GeocodeError) { @custom_loc_a.distance_to("Irving, TX")  }
  end
  
  def test_custom_attributes_distance_calculations
    assert_equal 0, @custom_loc_a.distance_to(@loc_a)
    assert_equal 0, CustomLocation.distance_between(@custom_loc_a, @loc_a)
  end
  
  def test_distance_column_in_select
    locations = Location.find(:all, :origin => @loc_a, :order => "distance ASC")
    assert_equal 6, locations.size
    assert_equal 0, @loc_a.distance_to(locations.first)
    assert_in_delta 3.97, @loc_a.distance_to(locations.last, :units => :miles, :formula => :sphere), 0.01
  end
  
  def test_find_with_distance_condition
    locations = Location.find(:all, :origin => @loc_a, :conditions => "distance < 3.97")
    assert_equal 5, locations.size
  end 
  
  def test_find_with_distance_condition_with_units_override
    locations = Location.find(:all, :origin => @loc_a, :units => :kms, :conditions => "distance < 6.387")
    assert_equal 5, locations.size
  end
  
  def test_find_with_distance_condition_with_formula_override
    locations = Location.find(:all, :origin => @loc_a, :formula => :flat, :conditions => "distance < 6.387")
    assert_equal 6, locations.size
  end
  
  def test_find_within
    locations = Location.find_within(3.97, :origin => @loc_a)
    assert_equal 5, locations.size    
  end
  
  def test_find_within_with_coordinates
    locations = Location.find_within(3.97, :origin =>[@loc_a.lat,@loc_a.lng])
    assert_equal 5, locations.size    
  end
  
  def test_find_with_compound_condition
    locations = Location.find(:all, :origin => @loc_a, :conditions => "distance < 5 and city = 'Coppell'")
    assert_equal 2, locations.size
  end
  
  def test_find_with_secure_compound_condition
    locations = Location.find(:all, :origin => @loc_a, :conditions => ["distance < ? and city = ?", 5, 'Coppell'])
    assert_equal 2, locations.size
  end
  
  def test_find_beyond
    locations = Location.find_beyond(3.95, :origin => @loc_a)
    assert_equal 1, locations.size    
  end
  
  def test_find_beyond_with_coordinates
    locations = Location.find_beyond(3.95, :origin =>[@loc_a.lat, @loc_a.lng])
    assert_equal 1, locations.size    
  end
  
  def test_find_nearest
    assert_equal @loc_a, Location.find_nearest(:origin => @loc_a)
  end
  
  def test_find_nearest_with_coordinates
    assert_equal @loc_a, Location.find_nearest(:origin =>[@loc_a.lat, @loc_a.lng])
  end
  
  def test_find_farthest
    assert_equal @loc_e, Location.find_farthest(:origin => @loc_a)
  end
  
  def test_find_farthest_with_coordinates
    assert_equal @loc_e, Location.find_farthest(:origin =>[@loc_a.lat, @loc_a.lng])
  end
  
  def test_scoped_distance_column_in_select
    locations = @starbucks.locations.find(:all, :origin => @loc_a, :order => "distance ASC")
    assert_equal 5, locations.size
    assert_equal 0, @loc_a.distance_to(locations.first)
    assert_in_delta 3.97, @loc_a.distance_to(locations.last, :units => :miles, :formula => :sphere), 0.01
  end
  
  def test_scoped_find_with_distance_condition
    locations = @starbucks.locations.find(:all, :origin => @loc_a, :conditions => "distance < 3.97")
    assert_equal 4, locations.size
  end 
  
  def test_scoped_find_within
    locations = @starbucks.locations.find_within(3.97, :origin => @loc_a)
    assert_equal 4, locations.size    
  end
  
  def test_scoped_find_with_compound_condition
    locations = @starbucks.locations.find(:all, :origin => @loc_a, :conditions => "distance < 5 and city = 'Coppell'")
    assert_equal 2, locations.size
  end
  
  def test_scoped_find_beyond
    locations = @starbucks.locations.find_beyond(3.95, :origin => @loc_a)
    assert_equal 1, locations.size    
  end
  
  def test_scoped_find_nearest
    assert_equal @loc_a, @starbucks.locations.find_nearest(:origin => @loc_a)
  end
  
  def test_scoped_find_farthest
    assert_equal @loc_e, @starbucks.locations.find_farthest(:origin => @loc_a)
  end  
  
  def test_ip_geocoded_distance_column_in_select
    GeoKit::Geocoders::IpGeocoder.expects(:geocode).with(LOCATION_A_IP).returns(@location_a)
    locations = Location.find(:all, :origin => LOCATION_A_IP, :order => "distance ASC")
    assert_equal 6, locations.size
    assert_equal 0, @loc_a.distance_to(locations.first)
    assert_in_delta 3.97, @loc_a.distance_to(locations.last, :units => :miles, :formula => :sphere), 0.01
  end
  
  def test_ip_geocoded_find_with_distance_condition
    GeoKit::Geocoders::IpGeocoder.expects(:geocode).with(LOCATION_A_IP).returns(@location_a)
    locations = Location.find(:all, :origin => LOCATION_A_IP, :conditions => "distance < 3.97")
    assert_equal 5, locations.size
  end 
  
  def test_ip_geocoded_find_within
    GeoKit::Geocoders::IpGeocoder.expects(:geocode).with(LOCATION_A_IP).returns(@location_a)
    locations = Location.find_within(3.97, :origin => LOCATION_A_IP)
    assert_equal 5, locations.size    
  end
  
  def test_ip_geocoded_find_with_compound_condition
    GeoKit::Geocoders::IpGeocoder.expects(:geocode).with(LOCATION_A_IP).returns(@location_a)
    locations = Location.find(:all, :origin => LOCATION_A_IP, :conditions => "distance < 5 and city = 'Coppell'")
    assert_equal 2, locations.size
  end
  
  def test_ip_geocoded_find_with_secure_compound_condition
    GeoKit::Geocoders::IpGeocoder.expects(:geocode).with(LOCATION_A_IP).returns(@location_a)
    locations = Location.find(:all, :origin => LOCATION_A_IP, :conditions => ["distance < ? and city = ?", 5, 'Coppell'])
    assert_equal 2, locations.size
  end
  
  def test_ip_geocoded_find_beyond
    GeoKit::Geocoders::IpGeocoder.expects(:geocode).with(LOCATION_A_IP).returns(@location_a)
    locations = Location.find_beyond(3.95, :origin => LOCATION_A_IP)
    assert_equal 1, locations.size    
  end
  
  def test_ip_geocoded_find_nearest
    GeoKit::Geocoders::IpGeocoder.expects(:geocode).with(LOCATION_A_IP).returns(@location_a)
    assert_equal @loc_a, Location.find_nearest(:origin => LOCATION_A_IP)
  end
  
  def test_ip_geocoded_find_farthest
    GeoKit::Geocoders::IpGeocoder.expects(:geocode).with(LOCATION_A_IP).returns(@location_a)
    assert_equal @loc_e, Location.find_farthest(:origin => LOCATION_A_IP)
  end
  
  def test_ip_geocoder_exception
    GeoKit::Geocoders::IpGeocoder.expects(:geocode).with('127.0.0.1').returns(GeoKit::GeoLoc.new)
    assert_raises GeoKit::Geocoders::GeocodeError do
      Location.find_farthest(:origin => '127.0.0.1')
    end
  end
  
  def test_address_geocode
    GeoKit::Geocoders::MultiGeocoder.expects(:geocode).with('Irving, TX').returns(@location_a)  
    locations = Location.find(:all, :origin => 'Irving, TX', :conditions => ["distance < ? and city = ?", 5, 'Coppell'])
    assert_equal 2, locations.size
  end
  
  def test_find_with_custom_distance_condition
    locations = CustomLocation.find(:all, :origin => @loc_a, :conditions => "dist < 3.97")
    assert_equal 5, locations.size 
  end  
  
  def test_find_with_custom_distance_condition_using_custom_origin
    locations = CustomLocation.find(:all, :origin => @custom_loc_a, :conditions => "dist < 3.97")
    assert_equal 5, locations.size 
  end
  
  def test_find_within_with_custom
    locations = CustomLocation.find_within(3.97, :origin => @loc_a)
    assert_equal 5, locations.size    
  end
  
  def test_find_within_with_coordinates_with_custom
    locations = CustomLocation.find_within(3.97, :origin =>[@loc_a.lat, @loc_a.lng])
    assert_equal 5, locations.size    
  end
  
  def test_find_with_compound_condition_with_custom
    locations = CustomLocation.find(:all, :origin => @loc_a, :conditions => "dist < 5 and city = 'Coppell'")
    assert_equal 1, locations.size
  end
  
  def test_find_with_secure_compound_condition_with_custom
    locations = CustomLocation.find(:all, :origin => @loc_a, :conditions => ["dist < ? and city = ?", 5, 'Coppell'])
    assert_equal 1, locations.size
  end
  
  def test_find_beyond_with_custom
    locations = CustomLocation.find_beyond(3.95, :origin => @loc_a)
    assert_equal 1, locations.size    
  end
  
  def test_find_beyond_with_coordinates_with_custom
    locations = CustomLocation.find_beyond(3.95, :origin =>[@loc_a.lat, @loc_a.lng])
    assert_equal 1, locations.size    
  end
  
  def test_find_nearest_with_custom
    assert_equal @custom_loc_a, CustomLocation.find_nearest(:origin => @loc_a)
  end
  
  def test_find_nearest_with_coordinates_with_custom
    assert_equal @custom_loc_a, CustomLocation.find_nearest(:origin =>[@loc_a.lat, @loc_a.lng])
  end
  
  def test_find_farthest_with_custom
    assert_equal @custom_loc_e, CustomLocation.find_farthest(:origin => @loc_a)
  end
  
  def test_find_farthest_with_coordinates_with_custom
    assert_equal @custom_loc_e, CustomLocation.find_farthest(:origin =>[@loc_a.lat, @loc_a.lng])
  end
  
  def test_find_with_array_origin
    locations = Location.find(:all, :origin =>[@loc_a.lat,@loc_a.lng], :conditions => "distance < 3.97")
    assert_equal 5, locations.size
  end
end
