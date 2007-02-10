module GeoKit
  # Contains the class method acts_as_mappable targeted to be mixed into ActiveRecord.
  # When mixed in, augments find services such that they provide distance calculation
  # query services.  The find method accepts additional options:
  #
  # * :origin - which contains an object which has lat and lng attributes
  # * :lat, :lng - in lieue of an origin, specific lat and lng attributes can be specified
  # 
  # Other finder methods are provided for specific queries.  These are:
  #
  # * find_within (alias: find_inside)
  # * find_beyond (alias: find_outside)
  # * find_closest (alias: find_nearest)
  # * find_farthest
  #
  # If raw SQL is desired, the distance_sql method can be used to obtain SQL appropriate
  # to use in a find_by_sql call.
  module ActsAsMappable 
    # Mix below class methods into ActiveRecord.
    def self.included(base) # :nodoc:
      base.extend ClassMethods
    end
    
    # Class method to mix into active record.
    module ClassMethods # :nodoc:
      # Class method to bring distance query support into ActiveRecord models.  By default
      # uses :miles for distance units and performs calculations based upon the Haversine
      # (sphere) formula.  Also, by default, uses lat, lng, and distance for respective
      # column names.  All of these can be overridden using the :default_units, :default_formula,
      # :lat_column_name, :lng_column_name, and :distance_column_name hash keys.
      def acts_as_mappable(options = {})
        # Mix in the module, but ensure to do so just once.
        return if self.included_modules.include?(GeoKit::ActsAsMappable::InstanceMethods)
        send :include, GeoKit::ActsAsMappable::InstanceMethods
        # include the Mappable module.
        send :include, Mappable
        
        # Handle class variables.
        cattr_accessor :distance_column_name, :default_units, :default_formula, :lat_column_name, :lng_column_name
        self.distance_column_name = options[:distance_column_name]  || 'distance'
        self.default_units = options[:default_units] || :miles
        self.default_formula = options[:default_formula] || :sphere
        self.lat_column_name = options[:lat_column_name] || 'lat'
        self.lng_column_name = options[:lng_column_name] || 'lng'
      end
    end
    
    # Instance methods to mix into ActiveRecord.
    module InstanceMethods #:nodoc:    
      # Mix class methods into module.
      def self.included(base) # :nodoc:
        base.extend SingletonMethods
      end
      
      # Class singleton methods to mix into ActiveRecord.
      module SingletonMethods # :nodoc:
        # Extends the existing find method in potentially two ways:
        # - If a mappable instance exists in the options, adds a distance column.
        # - If a mappable instance exists in the options and the distance column exists in the
        #   conditions, substitutes the distance sql for the distance column -- this saves
        #   having to write the gory SQL.
        def find(*args)
          options = extract_options_from_args!(args)
          origin = extract_origin_from_options(options)
          add_distance_to_select(options, origin) if origin
          substitute_distance_in_conditions(options, origin) if origin && options.has_key?(:conditions)
          args.push(options)
          super(*args)
        end     
        
        # Finds within a distance radius.
        def find_within(distance, options={})
          origin = extract_origin_from_options(options)
          find(:all, :origin => origin, :conditions => "#{distance_column_name} <= #{distance}", :order => "#{distance_column_name} ASC")
        end
        alias find_inside find_within
        
        # Finds beyond a distance radius.
        def find_beyond(distance, options={})
          origin = extract_origin_from_options(options)
          find(:all, :origin => origin, :conditions => "#{distance_column_name} > #{distance}", :order => "#{distance_column_name} ASC")
        end
        alias find_outside find_beyond
        
        # Finds the closest to the origin.
        def find_closest(options={})
          origin = extract_origin_from_options(options)
          find(:first, :origin => origin, :order => "#{distance_column_name} ASC")
        end
        alias find_nearest find_closest
        
        # Finds the farthest from the origin.
        def find_farthest(options={})
          origin = extract_origin_from_options(options)
          find(:first, :origin => origin, :order => "#{distance_column_name} DESC")
        end
        
        # Returns the distance calculation to be used as a display column or a condition.  This
        # is provide for anyone wanting access to the raw SQL.
        def distance_sql(origin, units=default_units, formula=default_formula)
          case formula
          when :sphere
            sql = sphere_distance_sql(origin, units)
          when :flat
            sql = flat_distance_sql(origin, units)
          end
          sql
        end   

        private

        # Extracts the origin instance out of the options if it exists and returns
        # it.  If there is no origin, looks for latitude and longitude values to 
        # create an origin.  The side-effect of the method is to remove these 
        # option keys from the hash.
        def extract_origin_from_options(options)
          origin = options[:origin]
          origin = geocode_origin(origin) if origin && origin.is_a?(String)
          unless origin  
            origin = GeoKit::LatLng.new(options[:lat], options[:lng]) if options[:lat] && options[:lng]
          end
          [:origin, :lat, :lng].each {|option| options.delete(option)}
          origin
        end
        
        # Geocodes the origin which was passed in String form.  The string needs
        # to be classified so that the appropriate geocoding technique can be 
        # used.  Strings can be either IP addresses or physical addresses.  The
        # result is a LatLng which substitutes in for the origin.
        def geocode_origin(origin)
          geo_origin = geocode_ip_address(origin) if /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})?$/.match(origin)
          geo_origin = geocode_physical_address(origin) unless geo_origin
          geo_origin
        end

       # Geocode IP address.
        def geocode_ip_address(origin)
          geo_location = GeoKit::Geocoders::IpGeocoder.geocode(origin)
          return geo_location if geo_location.success
          raise GeoKit::Geocoders::GeocodeError
        end
        
        # Geocode physical address.
        def geocode_physical_address(origin)
          res = GeoKit::Geocoders::MultiGeocoder.geocode(origin)
          return res if res.success
          raise GeoKit::Geocoders::GeocodeError 
        end

        # Augments the select with the distance SQL.
        def add_distance_to_select(options, origin)
          if origin
            distance_selector = distance_sql(origin, default_units, default_formula) + " AS #{distance_column_name}"
            selector = options.has_key?(:select) && options[:select] ? options[:select] : "*"
            options[:select] = "#{selector}, #{distance_selector}"  
          end   
        end

        # Looks for the distance column and replaces it with the distance sql. If an origin was not 
        # passed in and the distance column exists, we leave it to be flagged as bad SQL by the database.
        # Conditions are either a string or an array.  In the case of an array, the first entry contains
        # the condition.
        def substitute_distance_in_conditions(options, origin)
          original_conditions = options[:conditions]
          condition = original_conditions.is_a?(String) ? original_conditions : original_conditions.first
          pattern = Regexp.new("\s*#{distance_column_name}(\s<>=)*")
          condition = condition.gsub(pattern, distance_sql(origin, default_units, default_formula))
          original_conditions = condition if original_conditions.is_a?(String)
          original_conditions[0] = condition if original_conditions.is_a?(Array)
          options[:conditions] = original_conditions
        end
        
        # Returns the distance SQL using the spherical world formula (Haversine).  The SQL is tuned
        # to the database in use.
        def sphere_distance_sql(origin, units)
          lat = deg2rad(extract_latitude(origin))
          lng = deg2rad(extract_longitude(origin))
          multiplier = units_sphere_multiplier(units)
          case connection.adapter_name.downcase
          when "mysql"
            sql=<<-SQL_END 
                  (ACOS(COS(#{lat})*COS(#{lng})*COS(RADIANS(#{lat_column_name}))*COS(RADIANS(#{lng_column_name}))+
                  COS(#{lat})*SIN(#{lng})*COS(RADIANS(#{lat_column_name}))*SIN(RADIANS(#{lng_column_name}))+
                  SIN(#{lat})*SIN(RADIANS(#{lat_column_name})))*#{multiplier})
                  SQL_END
          when "postgresql"
            sql=<<-SQL_END 
                  (ACOS(COS(#{lat})*COS(#{lng})*COS(RADIANS(#{lat_column_name}))*COS(RADIANS(#{lng_column_name}))+
                  COS(#{lat})*SIN(#{lng})*COS(RADIANS(#{lat_column_name}))*SIN(RADIANS(#{lng_column_name}))+
                  SIN(#{lat})*SIN(RADIANS(#{lat_column_name})))*#{multiplier})
                  SQL_END
          else
            sql = "unhandled #{connection.adapter_name.downcase} adapter"
          end        
        end
        
        # Returns the distance SQL using the flat-world formula (Phythagorean Theory).  The SQL is tuned
        # to the database in use.
        def flat_distance_sql(origin, units)
          lat = extract_latitude(origin) 
          lat_degree_units = units_per_latitude_degree(units)
          lng = extract_longitude(origin)
          lng_degree_units = units_per_longitude_degree(lat, units)
          case connection.adapter_name.downcase
          when "mysql"
            sql=<<-SQL_END
                  SQRT(POW(#{lat_degree_units}*(#{lat}-#{lat_column_name}),2)+
                  POW(#{lng_degree_units}*(#{lng}-#{lng_column_name}),2))
                  SQL_END
          when "postgresql"
            sql=<<-SQL_END
                  SQRT(POW(#{lat_degree_units}*(#{lat}-#{lat_column_name}),2)+
                  POW(#{lng_degree_units}*(#{lng}-#{lng_column_name}),2))
                  SQL_END
          else
            sql = "unhandled #{connection.adapter_name.downcase} adapter"
          end
        end
        
        # Extract the latitude from the origin by trying the lat or latitude methods first
        # and then making the assumption this is an instance of the kind of classes we are
        # trying to find.
        def extract_latitude(origin)
          return origin.lat if origin.methods.include?('lat')
          return origin.latitude if origin.methods.include?('latitude')
          return eval("origin.#{lat_column_name}") if origin.instance_of?(self)
        end
        
        # Extract the longitude from the origin by trying the lng or longitude methods first
        # and then making the assumption this is an instance of the kind of classes we are
        # trying to find.
        def extract_longitude(origin)
          return origin.lng if origin.methods.include?('lng')
          return origin.longitude if origin.methods.include?('longitude')    
          return eval("origin.#{lng_column_name}") if origin.instance_of?(self)      
        end
      end
    end
  end
end 