module GeoKit
  # Contains class and instance methods providing distance calcuation services.  This
  # module is meant to be mixed into classes containing lat and lng attributes where
  # distance calculation is desired.  
  # 
  # At present, two forms of distance calculations are provided:
  # 
  # * Pythagorean Theory (flat Earth) - which assumes the world is flat and loses accuracy over long distances.
  # * Haversine (sphere) - which is fairly accurate, but at a performance cost.
  # 
  # Distance units supported are :miles and :kms.
  module Mappable
    PI_DIV_RAD = 0.0174
    KMS_PER_MILE = 1.609
    EARTH_RADIUS_IN_MILES = 3963
    EARTH_RADIUS_IN_KMS = EARTH_RADIUS_IN_MILES * KMS_PER_MILE
    MILES_PER_LATITUDE_DEGREE = 69.1
    KMS_PER_LATITUDE_DEGREE = MILES_PER_LATITUDE_DEGREE * KMS_PER_MILE
    LATITUDE_DEGREES = EARTH_RADIUS_IN_MILES / MILES_PER_LATITUDE_DEGREE  
    
    # Mix below class methods into the includer.
    def self.included(receiver) # :nodoc:
      receiver.extend ClassMethods
    end   
    
    module ClassMethods #:nodoc:
      # Returns the distance between two points.  The from and to parameters are
      # required to have lat and lng attributes.  Valid options are:
      # :units - valid values are :miles or :kms (:miles is the default)
      # :formula - valid values are :flat or :sphere (:sphere is the default)
      def distance_between(from, to, options={})
        units = options[:units]  || :miles
        formula = options[:formula] || :sphere
        case formula
        when :sphere          
          units_sphere_multiplier(units) * 
              Math.acos( Math.sin(deg2rad(get_lat(from))) * Math.sin(deg2rad(get_lat(to))) + 
              Math.cos(deg2rad(get_lat(from))) * Math.cos(deg2rad(get_lat(to))) * 
              Math.cos(deg2rad(get_lng(to)) - deg2rad(get_lng(from))))   
        when :flat
          Math.sqrt((units_per_latitude_degree(units)*(get_lat(from)-get_lat(to)))**2 + 
              (units_per_longitude_degree(get_lat(from), units)*(get_lng(from)-get_lng(to)))**2)
        end
      end
    
      protected
    
      def deg2rad(degrees)
        degrees / 180 * Math::PI
      end

      # Returns the multiplier used to obtain the correct distance units.
      def units_sphere_multiplier(units)
        units == :miles ? EARTH_RADIUS_IN_MILES : EARTH_RADIUS_IN_KMS
      end

      # Returns the number of units per latitude degree.
      def units_per_latitude_degree(units)
        units == :miles ? MILES_PER_LATITUDE_DEGREE : KMS_PER_LATITUDE_DEGREE
      end
    
      # Returns the number units per longitude degree.
      def units_per_longitude_degree(lat, units)
        miles_per_longitude_degree = (LATITUDE_DEGREES * Math.cos(lat * PI_DIV_RAD)).abs
        units == :miles ? miles_per_longitude_degree : miles_per_longitude_degree * KMS_PER_MILE
      end
      
      # Ensure proper latitude is returned for Mappable instances that have invoked acts_as_mappable
      # and potentially customized the latitude attribute.  Otherwise, fall back to default lat
      # attribute.
      def get_lat(point)
        acting_as_mappable?(point) ? eval("point.#{point.class.lat_column_name}") : point.lat
      end
      
      # Ensure proper longitude is returned for Mappable instances that have invoked acts_as_mappable
      # and potentially customized the longitude attribute.  Otherwise, fall back to default lng
      # attribute.
      def get_lng(point)
        acting_as_mappable?(point) ? eval("point.#{point.class.lng_column_name}") : point.lng
      end
      
      # Returns true if the object knows acts_as_mappable and has actually invoked it.  Using the 
      # class attribute distance_column_name as a marker attribute.
      def acting_as_mappable?(point)
        point.class.respond_to?(:acts_as_mappable) && point.class.respond_to?(:distance_column_name)
      end
    end
  
    # Returns the distance from another point.  The other point parameter is
    # required to have lat and lng attributes.  Valid options are:
    # :units - valid values are :miles or :kms (:miles is the default)
    # :formula - valid values are :flat or :sphere (:sphere is the default)
    def distance_to(other, options={})
      self.class.distance_between(self, other, options)
    end  
    alias distance_from distance_to
  end

  class LatLng 
    include Mappable

    attr_accessor :lat, :lng

    # Accepts latitude and longitude or instantiates an empty instance
    # if lat and lng are not provided.
    def initialize(lat=nil, lng=nil)
      @lat = lat
      @lng = lng
    end 

    # Latitude attribute setter; stored as a float.
    def lat=(lat)
      @lat = lat.to_f if lat
    end

    # Longitude attribute setter; stored as a float;
    def lng=(lng)
      @lng=lng.to_f if lng
    end  

    # Returns the lat and lng attributes as a comma-separated string.
    def ll
      "#{lat},#{lng}"
    end  

    # Returns true if the candidate object is logically equal.  Logical equivalence
    # is true if the lat and lng attributes are the same for both objects.
    def ==(other)
      other.nil? ? false : self.lat == other.lat && self.lng == other.lng
    end
  end

  # This class encapsulates the result of a geocoding call
  # It's primary purpose is to homogenize the results of multiple
  # geocoding providers. It also provides some additional functionality, such as 
  # the "full address" method for geocoders that do not provide a 
  # full address in their results (for example, Yahoo), and the "is_us" method.
  class GeoLoc < LatLng
    # Location attributes.  Full address is a concatenation of all values.  For example:
    # 100 Spear St, San Francisco, CA, 94101, US
    attr_accessor :street_address, :city, :state, :zip, :country_code, :full_address
    # Attributes set upon return from geocoding.  Success will be true for successful
    # geocode lookups.  The provider will be set to the name of the providing geocoder.
    # Finally, precision is an indicator of the accuracy of the geocoding.
    attr_accessor :success, :provider, :precision
    # Street number and street name are extracted from the street address attribute.
    attr_reader :street_number, :street_name

    # Constructor expects a hash of symbols to correspond with attributes.
    def initialize(h={})
      @street_address=h[:street_address] 
      @city=h[:city] 
      @state=h[:state] 
      @zip=h[:zip] 
      @country_code=h[:country_code] 
      @success=false
      @precision='unknown'
      super(h[:lat],h[:lng])
    end

    # Returns true if geocoded to the United States.
    def is_us?
      country_code == 'US'
    end

    # full_address is provided by google but not by yahoo. It is intended that the google
    # geocoding method will provide the full address, whereas for yahoo it will be derived
    # from the parts of the address we do have.
    def full_address
      @full_address ? @full_address : to_geocodeable_s
    end

    # Extracts the street number from the street address if the street address
    # has a value.
    def street_number
      street_address[/(\d*)/] if street_address
    end

    # Returns the street name portion of the street address.
    def street_name
       street_address[street_number.length, street_address.length].strip if street_address
    end

    # gives you all the important fields as key-value pairs
    def hash
      res={}
      [:success,:lat,:lng,:country_code,:city,:state,:zip,:street_address,:provider,:full_address,:ll,:is_us,:precision].each {|s|res[s]=self.send(s.to_s)}
      res
    end

    # Sets the city after capitalizing each word within the city name.
    def city=(city)
      @city = city.titleize if city
    end

    # Sets the street address after capitalizing each word within the street address.
    def street_address=(address)
      @street_address = address.titleize if address
    end  

    # Returns a comma-delimited string consisting of the street address, city, state,
    # zip, and country code.  Only includes those attributes that are non-blank.
    def to_geocodeable_s
      a=[street_address,city,state,zip,country_code].compact
      a.delete_if {|e| !e|| e==''}
      a.join(', ')      
    end

    # Returns a string representation of the instance.
    def to_s
      "Provider: #{provider}\n Street: #{street_address}\nCity: #{city}\nState: #{state}\nZip: #{zip}\nLatitude: #{lat}\nLongitude: #{lng}\nCountry: #{country_code}\nSuccess: #{success}"
    end
  end
end