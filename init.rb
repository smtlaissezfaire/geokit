require File.dirname(__FILE__) + '/lib/geo_kit/defaults'
require File.dirname(__FILE__) + '/lib/geo_kit/acts_as_mappable'
require File.dirname(__FILE__) + '/lib/geo_kit/ip_geocode_lookup'
require File.dirname(__FILE__) + '/lib/geo_kit/geocoders'
require File.dirname(__FILE__) + '/lib/geo_kit/mappable'
ActiveRecord::Base.send :include, GeoKit::ActsAsMappable
ActionController::Base.send :include, GeoKit::IpGeocodeLookup
