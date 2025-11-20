require "./block"
require "json"

class Blockchain
  getter chain : Array(Block)
  FILE_NAME = "blockchain.json"

  def initialize
    @chain = load_chain
  end

  def create_genesis_block
    Block.new(0, "GENESIS", "SYSTEM", "0")
  end

  def last_block
    @chain.last
  end

  def add_dataset(dataset_hash : String, owner : String) : Tuple(Block, Bool)
    existing = @chain.find { |b| b.dataset_hash == dataset_hash }
    if existing
      return {existing, false}
    end

    new_block = Block.new(
      last_block.index + 1,
      dataset_hash,
      owner,
      last_block.hash
    )

    @chain << new_block
    save_chain

    {new_block, true}
  end

  def exists?(dataset_hash : String)
    @chain.any? { |b| b.dataset_hash == dataset_hash }
  end

  private def save_chain
    File.write(FILE_NAME, @chain.map(&.to_json).join("\n"))
  end

  private def load_chain : Array(Block)
    if File.exists?(FILE_NAME)
      File.read(FILE_NAME).split("\n").map { |line| Block.from_json(line) }
    else
      [create_genesis_block]
    end
  end
end
