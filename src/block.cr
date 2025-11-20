require "time"
require "json"
require "digest/sha256"

class Block
  getter index : Int32
  getter timestamp : Time
  getter dataset_hash : String
  getter owner : String
  getter previous_hash : String
  getter hash : String

  def initialize(index : Int32, dataset_hash : String, owner : String, previous_hash : String)
    @index = index
    @timestamp = Time.utc
    @dataset_hash = dataset_hash
    @owner = owner
    @previous_hash = previous_hash
    @hash = calculate_hash
  end

  def calculate_hash
     Digest::SHA256.hexdigest("#{@index}#{@timestamp}#{@dataset_hash}#{@owner}#{@previous_hash}")
  end

  def to_json
    {
      "index" => @index,
      "timestamp" => @timestamp.to_s,
      "dataset_hash" => @dataset_hash,
      "owner" => @owner,
      "previous_hash" => @previous_hash,
      "hash" => @hash
    }.to_json
  end

  def self.from_json(json_str : String)
    data = JSON.parse(json_str)
    Block.new(
    data["index"].as_i,        
    data["dataset_hash"].as_s,
    data["owner"].as_s,
    data["previous_hash"].as_s
    )
  end
end
