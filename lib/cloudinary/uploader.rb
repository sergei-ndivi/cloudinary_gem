# Copyright Cloudinary
require 'rest_client'
require 'json'

class Cloudinary::Uploader
  
  def self.upload(file, options={})
    call_api("upload", options) do    
      params = {:timestamp=>Time.now.to_i,
                :transformation => Cloudinary::Utils.generate_transformation_string(options),
                :public_id=> options[:public_id],
                :callback=> options[:callback],
                :format=>options[:format],
                :tags=>options[:tags] && Cloudinary::Utils.build_array(options[:tags]).join(",")}.reject{|k,v| v.blank?}    
      if options[:eager]
        params[:eager] = options[:eager].map do
          |transformation, format|
          [Cloudinary::Utils.generate_transformation_string(transformation.clone), format].compact.join("/")
        end.join("|")
      end
      if file.respond_to?(:read) || file =~ /^https?:/
        params[:file] = file
      else 
        params[:file] = File.open(file, "rb")
      end
      [params, [:file]]
    end              
  end

  def self.destroy(public_id, options={})
    call_api("destroy", options) do    
      {
        :timestamp=>Time.now.to_i,
        :public_id=> public_id
      }
    end              
  end
    
  def self.generate_sprite(tag, options={})
    version_store = options.delete(:version_store)
    
    result = call_api("sprite", options) do
      {
        :timestamp=>Time.now.to_i,
        :tag=>tag,
        :transformation => Cloudinary::Utils.generate_transformation_string(options)
      }    
    end
    
    if version_store == :file && result && result["version"]
      if defined?(Rails) && defined?(Rails.root)
        FileUtils.mkdir_p("#{Rails.root}/tmp/cloudinary")
        File.open("#{Rails.root}/tmp/cloudinary/cloudinary_sprite_#{tag}.version", "w"){|file| file.print result["version"].to_s}                      
      end  
    end      
    return result
  end
  
  # options may include 'exclusive' (boolean) which causes clearing this tag from all other resources 
  def self.add_tag(tag, public_ids = [], options = {})
    exclusive = options.delete(:exclusive)
    command = exclusive ? "set_exclusive" : "add"
    return self.call_tags_api(tag, command, public_ids, options)    
  end

  def self.remove_tag(tag, public_ids = [], options = {})
    return self.call_tags_api(tag, "remove", public_ids, options)    
  end

  def self.replace_tag(tag, public_ids = [], options = {})
    return self.call_tags_api(tag, "replace", public_ids, options)    
  end
  
  private
  
  def self.call_tags_api(tag, command, public_ids = [], options = {})
    return call_api("tags", options) do
      {
        :timestamp=>Time.now.to_i,
        :tag=>tag,
        :public_ids => Cloudinary::Utils.build_array(public_ids),
        :command => command
      }    
    end    
  end
     
  def self.call_api(action, options)
    options = options.clone
    return_error = options.delete(:return_error)
    api_key = options[:api_key] || Cloudinary.config.api_key || raise("Must supply api_key")
    api_secret = options[:api_secret] || Cloudinary.config.api_secret || raise("Must supply api_secret")

    params, non_signable = yield
    non_signable ||= []
    
    params[:signature] = Cloudinary::Utils.api_sign_request(params.reject{|k,v| non_signable.include?(k)}, api_secret)
    params[:api_key] = api_key
    cloudinary = options.delete(:upload_prefix) || Cloudinary.config.upload_prefix || "https://api.cloudinary.com"

    resource_type = options.delete(:resource_type) || "image"
    result = nil
    cloud_name = Cloudinary.config.cloud_name || raise("Must supply cloud_name")
    RestClient::Request.execute(:method => :post, :url => "#{cloudinary}/v1_1/#{cloud_name}/#{resource_type}/#{action}", :payload => params, :timeout=>60) do
      |response, request, tmpresult|
      raise "Server returned unexpected status code - #{response.code} - #{response.body}" if ![200,400,500].include?(response.code)
      begin
        result = Cloudinary::Utils.json_decode(response.body)
      rescue => e
        # Error is parsing json
        raise "Error parsing server response (#{response.code}) - #{response.body}. Got - #{e}"
      end
      if result["error"]
        if return_error
          result["error"]["http_code"] = response.code
        else
          raise result["error"]["message"]
        end
      end        
    end
    
    result    
  end
end