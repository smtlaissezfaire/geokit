module GeoKit
  # Contains the class method acts_as_mappable targeted to be mixed into ActiveRecord.
  # When mixed in, augments find services such that they provide distance calculation
  # query services.  The find method accepts additional options:
  #
  # * :origin - can be 
  #   1. a two-element array of latititude/longitude -- :origin=>[37.792,-122.393]
  #   2. a geocodeable string -- :origin=>'100 Spear st, San Francisco, CA'
  #   3. an object which responds to lat and lng methods, or latitude and longitude methods,
  #      or whatever methods you have specified for lng_column_name and lat_column_name
  #      
  # Other finder methods are provided for specific queries.  These are:
  #
  # * find_within (alias: find_inside)
  # * find_beyond (alias: find_outside)
  # * find_closest (alias: find_nearest)
  # * find_farthest
  #
  # Counter methods are available and work similarly to finders.  
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
      # (sphere) formula.  These can be changed by setting GeoKit::default_units and
      # GeoKit::default_formula.  Also, by default, uses lat, lng, and distance for respective
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
        self.default_units = options[:default_units] || GeoKit::default_units
        self.default_formula = options[:default_formula] || GeoKit::default_formula
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
          prepare_for_find_or_count(:find, args)
          super(*args)
        end     
        
        # Extends the existing count method by:
        # - If a mappable instance exists in the options and the distance column exists in the
        #   conditions, substitutes the distance sql for the distance column -- this saves
        #   having to write the gory SQL.
        def count(*args)
          prepare_for_find_or_count(:count, args)
          super(*args)
        end
        
        # Finds within a distance radius.
        def find_within(distance, options={})
          options[:within] = distance
          find(:all, options)
        end
        alias find_inside find_within
        
        # Finds beyond a distance radius.
        def find_beyond(distance, options={})
          options[:beyond] = distance
          find(:all, options)
        end
        alias find_outside find_beyond
        
        # Finds according to a range.  Accepts inclusive or exclusive ranges.
        def find_by_range(range, options={})
          options[:range] = range
          find(:all, options)
        end
        
        # Finds the closest to the origin.
        def find_closest(options={})
          find(:nearest, options)
        end
        alias find_nearest find_closest
        
        # Finds the farthest from the origin.
        def find_farthest(options={})
          find(:farthest, options)
        end
        
        # counts within a distance radius.
        def count_within(distance, options={})
          options[:within] = distance
          count(options)
        end
        alias count_inside count_within
        
        # Counts beyond a distance radius.
        def count_beyond(distance, options={})
          options[:beyond] = distance
          count(options)
        end
        alias count_outside count_beyond
        
        # Counts according to a range.  Accepts inclusive or exclusive ranges.
        def count_by_range(range, options={})
          options[:range] = range
          count(options)
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
        
        # Prepares either a find or a count action by parsing through the options and
        # conditionally adding to the select clause for finders.
        def prepare_for_find_or_count(action, args)
          options = extract_options_from_args!(args)
          # Obtain items affecting distance condition.
          origin = extract_origin_from_options(options)
          units = extract_units_from_options(options)
          formula = extract_formula_from_options(options)
          # Apply select adjustments based upon action.
          add_distance_to_select(options, origin, units, formula) if origin && action == :find
          # Apply distance scoping and perform substitutions.
          apply_distance_scope(options)
          substitute_distance_in_conditions(options, origin, units, formula) if origin && options.has_key?(:conditions)
          # Order by scoping for find action.
          apply_find_scope(args, options) if action == :find
          # Restore options minus the extra options that we used for the
          # GeoKit API.
          args.push(options)   
        end
        
        # Looks for mapping-specific tokens and makes appropriate translations so that the 
        # original finder has its expected arguments.  Resets the the scope argument to 
        # :first and ensures the limit is set to one.
        def apply_find_scope(args, options)
          case args.first
            when :nearest
              args[0] = :first
              options[:limit] = 1
              options[:order] = "#{distance_column_name} ASC"
            when :farthest
              args[0] = :first
              options[:limit] = 1
              options[:order] = "#{distance_column_name} DESC"
          end
        end
        
        # Replace :within, :beyond and :range distance tokens with the appropriate distance 
        # where clauses.  Removes these tokens from the options hash.
        def apply_distance_scope(options)
          distance_condition = "#{distance_column_name} <= #{options[:within]}" if options.has_key?(:within)
          distance_condition = "#{distance_column_name} > #{options[:beyond]}" if options.has_key?(:beyond)
          distance_condition = "#{distance_column_name} >= #{options[:range].first} AND #{distance_column_name} <#{'=' unless options[:range].exclude_end?} #{options[:range].last}" if options.has_key?(:range)
          [:within, :beyond, :range].each { |option| options.delete(option) } if distance_condition
          if distance_condition && options.has_key?(:conditions)
            original_conditions = options[:conditions]
            condition = original_conditions.is_a?(String) ? original_conditions : original_conditions.first   
            condition = "#{distance_condition} AND #{condition}"       
            original_conditions = condition if original_conditions.is_a?(String)
            original_conditions[0] = condition if original_conditions.is_a?(Array)            
          elsif distance_condition
            options[:conditions] = distance_condition
          end
        end

        # Extracts the origin instance out of the options if it exists and returns
        # it.  If there is no origin, looks for latitude and longitude values to 
        # create an origin.  The side-effect of the method is to remove these 
        # option keys from the hash.
        def extract_origin_from_options(options)
          origin = options[:origin]
          if origin
              res = geocode_origin(origin) if origin.is_a?(String)
              res = GeoKit::LatLng.new(options[:origin][0], options[:origin][1]) if origin.is_a?(Array)
              res = GeoKit::LatLng.new(extract_latitude(origin), extract_longitude(origin)) unless res
          end
          options.delete(:origin)
          res
        end
        
        # Extract the units out of the options if it exists and returns it.  If
        # there is no :units key, it uses the default.  The side effect of the 
        # method is to remove the :units key from the options hash.
        def extract_units_from_options(options)
          units = options[:units] || default_units
          options.delete(:units)
          units
        end
        
        # Extract the formula out of the options if it exists and returns it.  If
        # there is no :formula key, it uses the default.  The side effect of the 
        # method is to remove the :formula key from the options hash.
        def extract_formula_from_options(options)
          formula = options[:formula] || default_formula
          options.delete(:formula)
          formula
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
        def add_distance_to_select(options, origin, units=default_units, formula=default_formula)
          if origin
            distance_selector = distance_sql(origin, units, formula) + " AS #{distance_column_name}"
            selector = options.has_key?(:select) && options[:select] ? options[:select] : "*"
            options[:select] = "#{selector}, #{distance_selector}"  
          end   
        end

        # Looks for the distance column and replaces it with the distance sql. If an origin was not 
        # passed in and the distance column exists, we leave it to be flagged as bad SQL by the database.
        # Conditions are either a string or an array.  In the case of an array, the first entry contains
        # the condition.
        def substitute_distance_in_conditions(options, origin, units=default_units, formula=default_formula)
          original_conditions = options[:conditions]
          condition = original_conditions.is_a?(String) ? original_conditions : original_conditions.first
          pattern = Regexp.new("\s*#{distance_column_name}(\s<>=)*")
          condition = condition.gsub(pattern, distance_sql(origin, units, formula))
          original_conditions = condition if original_conditions.is_a?(String)
          original_conditions[0] = condition if original_conditions.is_a?(Array)
          options[:conditions] = original_conditions
        end
        
        # Returns the distance SQL using the spherical world formula (Haversine).  The SQL is tuned
        # to the database in use.
        def sphere_distance_sql(origin, units)
          lat = deg2rad(origin.lat)
          lng = deg2rad(origin.lng)
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
          lat_degree_units = units_per_latitude_degree(units)
          lng_degree_units = units_per_longitude_degree(origin.lat, units)
          case connection.adapter_name.downcase
          when "mysql"
            sql=<<-SQL_END
                  SQRT(POW(#{lat_degree_units}*(#{origin.lat}-#{lat_column_name}),2)+
                  POW(#{lng_degree_units}*(#{origin.lng}-#{lng_column_name}),2))
                  SQL_END
          when "postgresql"
            sql=<<-SQL_END
                  SQRT(POW(#{lat_degree_units}*(#{origin.lat}-#{lat_column_name}),2)+
                  POW(#{lng_degree_units}*(#{origin.lng}-#{lng_column_name}),2))
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